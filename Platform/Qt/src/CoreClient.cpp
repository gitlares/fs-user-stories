// SPDX-License-Identifier: MIT
#include "CoreClient.h"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLoggingCategory>
#include <QTimer>

Q_LOGGING_CATEGORY(lcCoreClient, "fsuserstories.coreclient")

namespace fsuserstories {

namespace {

QVariantMap fromJson(const QJsonObject &object)
{
    // VariantMap <- JSON: keep nested objects as QVariantMap, arrays as QVariantList.
    QVariantMap result;
    for (auto it = object.constBegin(); it != object.constEnd(); ++it) {
        const QJsonValue value = it.value();
        if (value.isArray()) {
            result.insert(it.key(), value.toArray().toVariantList());
        } else if (value.isObject()) {
            result.insert(it.key(), value.toObject().toVariantMap());
        } else {
            result.insert(it.key(), value.toVariant());
        }
    }
    return result;
}

QByteArray serialise(const QVariantMap &command)
{
    return QJsonDocument(QJsonObject::fromVariantMap(command)).toJson(QJsonDocument::Compact);
}

} // namespace

CoreClient::CoreClient(const QString &executablePath,
                       const QStringList &extraArgs,
                       Mode mode,
                       QObject *parent)
    : QObject(parent)
    , m_executablePath(executablePath)
    , m_extraArgs(extraArgs)
    , m_mode(mode)
{
}

CoreClient::~CoreClient()
{
    shutdown();
}

bool CoreClient::startPersistent()
{
    if (m_mode != Mode::Persistent) {
        return false;
    }
    if (m_process) {
        return m_ready;
    }

    m_process = std::make_unique<QProcess>(this);
    m_process->setProgram(m_executablePath);
    m_process->setArguments(m_extraArgs);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);

    connect(m_process.get(), &QProcess::readyReadStandardError,
            this, &CoreClient::handleStderr);
    connect(m_process.get(),
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &CoreClient::handleFinished);
    connect(m_process.get(), &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError error) {
                if (m_stopping) {
                    return;
                }
                const QString message = (error == QProcess::FailedToStart)
                    ? QStringLiteral("Core failed to start: %1").arg(m_executablePath)
                    : QStringLiteral("Core process error: %1").arg(int(error));
                qCWarning(lcCoreClient) << message;
                emit coreError(message);
            });

    m_process->start();
    if (!m_process->waitForStarted(5000)) {
        qCWarning(lcCoreClient) << "Could not launch core at" << m_executablePath
                               << m_process->errorString();
        m_process.reset();
        return false;
    }

    // Send a no-op style probe (load_workspace with a non-existent path) to make
    // sure the core is alive. The core returns an error response, which is fine
    // for readiness — we only care that stdin/stdout round-tripped.
    writeCommand({{"command", "load_workspace"},
                  {"database_path", "/tmp/fs-user-stories-probe.sqlite"}});
    if (!m_process->waitForReadyRead(5000)) {
        qCWarning(lcCoreClient) << "Core did not respond to readiness probe";
        m_process->kill();
        m_process->waitForFinished();
        m_process.reset();
        return false;
    }
    QJsonParseError parseError;
    const QByteArray probeData = m_process->readAllStandardOutput();
    const auto probeDoc = QJsonDocument::fromJson(probeData, &parseError);
    if (parseError.error != QJsonParseError::NoError || !probeDoc.isObject()) {
        qCWarning(lcCoreClient) << "Core probe returned invalid JSON"
                                << probeData.left(120);
        m_process->kill();
        m_process->waitForFinished();
        m_process.reset();
        return false;
    }

    m_ready = true;
    emit coreReadyChanged(true);
    return true;
}

void CoreClient::shutdown()
{
    if (!m_process) {
        return;
    }
    m_stopping = true;
    m_process->closeWriteChannel();
    if (!m_process->waitForFinished(2000)) {
        m_process->terminate();
        if (!m_process->waitForFinished(1000)) {
            m_process->kill();
            m_process->waitForFinished();
        }
    }
    m_ready = false;
    m_process.reset();
    m_stopping = false;
    emit coreReadyChanged(false);
}

QVariantMap CoreClient::execute(const QVariantMap &command)
{
    if (m_mode == Mode::Persistent) {
        if (!m_process) {
            if (!startPersistent()) {
                return QVariantMap{
                    {"ok", false},
                    {"error", QVariantMap{
                        {"code", "core_missing"},
                        {"message", "Core process is not running."}}}};
            }
        }
        writeCommand(command);
        return readResponse();
    }

    // One-shot: spawn a fresh process, like the Swift bridge does.
    QProcess process;
    process.setProgram(m_executablePath);
    process.setArguments(m_extraArgs);
    process.setProcessChannelMode(QProcess::SeparateChannels);
    process.start();
    if (!process.waitForStarted(5000)) {
        return QVariantMap{
            {"ok", false},
            {"error", QVariantMap{
                {"code", "core_failed_to_start"},
                {"message", process.errorString()}}}};
    }
    process.write(serialise(command));
    process.closeWriteChannel();
    if (!process.waitForFinished(30000)) {
        process.kill();
        process.waitForFinished();
        return QVariantMap{
            {"ok", false},
            {"error", QVariantMap{
                {"code", "core_timeout"},
                {"message", "Core did not finish in time."}}}};
    }
    const QByteArray out = process.readAllStandardOutput();
    const QByteArray err = process.readAllStandardError();
    QJsonParseError parseError;
    const auto doc = QJsonDocument::fromJson(out, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return QVariantMap{
            {"ok", false},
            {"error", QVariantMap{
                {"code", "invalid_response"},
                {"message", QString::fromUtf8(err).isEmpty()
                             ? QStringLiteral("Core returned invalid JSON.")
                             : QString::fromUtf8(err).trimmed()}}}};
    }
    return fromJson(doc.object());
}

void CoreClient::executeAsync(const QVariantMap &command,
                              std::function<void(QVariantMap)> onCompleted,
                              std::function<void(QString)> onError)
{
    // Always use a dedicated one-shot process here. The persistent bridge is
    // intentionally synchronous, while UI actions must never wait on Git or
    // filesystem work in the main thread.
    auto *process = new QProcess(this);
    process->setProgram(m_executablePath);
    process->setArguments(m_extraArgs);
    process->setProcessChannelMode(QProcess::SeparateChannels);

    auto *timeout = new QTimer(process);
    timeout->setSingleShot(true);
    timeout->setInterval(30000);

    connect(process, &QProcess::started, process, [process, timeout, command]() {
        process->write(serialise(command));
        process->closeWriteChannel();
        timeout->start();
    });
    connect(process, &QProcess::errorOccurred, this,
            [process, timeout, onError](QProcess::ProcessError error) {
        if (process->property("completed").toBool() ||
            error != QProcess::FailedToStart) {
            return;
        }
        process->setProperty("completed", true);
        timeout->stop();
        if (onError) {
            onError(process->errorString());
        }
        process->deleteLater();
    });
    connect(timeout, &QTimer::timeout, this, [process, onError]() {
        if (process->property("completed").toBool()) {
            return;
        }
        process->setProperty("completed", true);
        process->kill();
        if (onError) {
            onError(QStringLiteral("Core did not finish in time."));
        }
        process->deleteLater();
    });
    connect(process,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this,
            [process, timeout, onCompleted, onError](int, QProcess::ExitStatus) {
        if (process->property("completed").toBool()) {
            return;
        }
        process->setProperty("completed", true);
        timeout->stop();

        const QByteArray output = process->readAllStandardOutput();
        const QByteArray errors = process->readAllStandardError();
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(output, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            if (onError) {
                const QString message = QString::fromUtf8(errors).trimmed();
                onError(message.isEmpty()
                            ? QStringLiteral("Core returned invalid JSON.")
                            : message);
            }
        } else if (onCompleted) {
            onCompleted(fromJson(document.object()));
        }
        process->deleteLater();
    });

    process->start();
}

void CoreClient::writeCommand(const QVariantMap &command)
{
    m_process->write(serialise(command));
    m_process->waitForBytesWritten(2000);
}

QVariantMap CoreClient::readResponse()
{
    if (!m_process->waitForReadyRead(30000)) {
        return QVariantMap{
            {"ok", false},
            {"error", QVariantMap{
                {"code", "core_timeout"},
                {"message", "Core did not respond in time."}}}};
    }
    const QByteArray data = m_process->readAllStandardOutput();
    QJsonParseError parseError;
    const auto doc = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        return QVariantMap{
            {"ok", false},
            {"error", QVariantMap{
                {"code", "invalid_response"},
                {"message", "Core returned invalid JSON."}}}};
    }
    return fromJson(doc.object());
}

void CoreClient::handleStderr()
{
    if (!m_process) {
        return;
    }
    const QByteArray data = m_process->readAllStandardError();
    if (!data.isEmpty()) {
        qCWarning(lcCoreClient) << "core stderr:" << data.trimmed();
    }
}

void CoreClient::handleFinished(int exitCode, QProcess::ExitStatus status)
{
    m_ready = false;
    emit coreReadyChanged(false);
    if (!m_stopping) {
        qCWarning(lcCoreClient) << "Core exited unexpectedly, code" << exitCode
                                << "status" << int(status);
        emit coreError(QStringLiteral("Core exited unexpectedly."));
    }
}

} // namespace fsuserstories
