// SPDX-License-Identifier: MIT
#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QProcess>
#include <memory>

namespace fsuserstories {

class CoreClient : public QObject
{
    Q_OBJECT
public:
    enum class Mode {
        /// Reuse a single running core process (recommended for the UI loop).
        Persistent,
        /// Spawn a fresh core per command (matches the original Swift bridge).
        OneShot
    };

    explicit CoreClient(const QString &executablePath,
                        const QStringList &extraArgs = {},
                        Mode mode = Mode::Persistent,
                        QObject *parent = nullptr);

    ~CoreClient() override;

    /// Returns true if the persistent process is up and responded to a handshake.
    bool isReady() const { return m_ready; }

    /// Synchronous JSON request. For UI workflows prefer the async variant.
    QVariantMap execute(const QVariantMap &command);

    /// Asynchronous JSON request. The reply delivers a parsed map with the
    /// fields `ok` (bool), `result` (QVariant) and `error` (QVariantMap).
    void executeAsync(const QVariantMap &command,
                      std::function<void(QVariantMap)> onSuccess,
                      std::function<void(QString)> onError);

    /// Attempts to start the persistent core process. Safe to call multiple times.
    bool startPersistent();

    /// Cleanly terminates the persistent core process.
    void shutdown();

signals:
    void coreReadyChanged(bool ready);
    void coreError(const QString &message);

private:
    void writeCommand(const QVariantMap &command);
    QVariantMap readResponse();
    void handleStderr();
    void handleFinished(int exitCode, QProcess::ExitStatus status);

    const QString m_executablePath;
    const QStringList m_extraArgs;
    const Mode m_mode;
    std::unique_ptr<QProcess> m_process;
    bool m_ready = false;
    bool m_stopping = false;
};

} // namespace fsuserstories
