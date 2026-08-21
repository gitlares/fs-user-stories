; SPDX-License-Identifier: MIT
; NSIS installer for FS User Stories (Qt front-end on Windows).
; Run after `Scripts/build-windows-app.ps1` (which stages the contents into
; `Distribution/Windows/fs-user-stories/`).

Unicode True
SetCompressor /SOLID lzma

!define APPNAME      "FS User Stories"
!define APPVERSION   "1.0.5"
!define PUBLISHER    "Pulser"
!define DESCRIPTION  "Local, offline-first user stories."
!define INSTALLDIR   "$LOCALAPPDATA\Programs\FS User Stories"

!ifndef PACKAGE_DIR
  !define PACKAGE_DIR "Distribution\Windows"
!endif

!ifndef OUTPUT_FILE
  !define OUTPUT_FILE "Distribution\Windows\FSUserStoriesSetup-${APPVERSION}-x64.exe"
!endif

Name       "${APPNAME} ${APPVERSION}"
OutFile    "${OUTPUT_FILE}"
InstallDir "${INSTALLDIR}"
RequestExecutionLevel user

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON   "${__FILEDIR__}\..\Platform\Qt\resources\fs-user-stories.ico"
!define MUI_UNICON "${__FILEDIR__}\..\Platform\Qt\resources\fs-user-stories.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\fs-user-stories.exe"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SectionIn RO
  ; The application normally remains in the tray when its window closes.
  ; Stop an older build before replacing it, then clear only the application
  ; directory. User projects and attachments live under LocalAppData outside
  ; this directory and are preserved.
  nsExec::ExecToLog '"$SYSDIR\taskkill.exe" /IM "fs-user-stories.exe" /T /F'
  RMDir /r "$INSTDIR"
  SetOutPath "$INSTDIR"
  ; /r recurses subdirectories; xp preserves long paths
  File /r "${PACKAGE_DIR}\fs-user-stories\*.*"

  ; Start menu entry
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" \
                 "$INSTDIR\fs-user-stories.exe"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" \
                 "$INSTDIR\fs-user-stories.exe"

  ; Uninstall program
  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "DisplayVersion" "${APPVERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "DisplayIcon" "$INSTDIR\fs-user-stories.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APPNAME}.lnk"
  RMDir /r "$INSTDIR"
  RMDir /r "$SMPROGRAMS\${APPNAME}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
SectionEnd
