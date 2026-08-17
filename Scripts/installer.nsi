; SPDX-License-Identifier: MIT
; NSIS installer for FS User Stories (Qt front-end on Windows).
; Run after `Scripts/build-windows-app.ps1` (which stages the contents into
; `Distribution/Windows/fs-user-stories/`).

Unicode True
SetCompressor /SOLID lzma

!define APPNAME      "FS User Stories"
!define APPVERSION   "0.1.0-alpha"
!define PUBLISHER    "Pulser"
!define DESCRIPTION  "Local, offline-first user stories."
!define INSTALLDIR   "$PROGRAMFILES64\FS User Stories"

Name       "${APPNAME} ${APPVERSION}"
OutFile    "Distribution\FSUserStoriesSetup-${APPVERSION}.exe"
InstallDir "${INSTALLDIR}"
RequestExecutionLevel admin

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON   "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SectionIn RO
  SetOutPath "$INSTDIR"
  ; /r recurses subdirectories; xp preserves long paths
  File /r "Distribution\Windows\fs-user-stories\*.*"

  ; Start menu entry
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" \
                 "$INSTDIR\fs-user-stories.exe"

  ; Uninstall program
  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "DisplayVersion" "${APPVERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}" \
               "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
SectionEnd

Section "Uninstall"
  RMDir /r "$INSTDIR"
  RMDir /r "$SMPROGRAMS\${APPNAME}"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
SectionEnd
