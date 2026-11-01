# What WittyMediaClient adds to the standard Windows setup and uninstaller. Uninstalling removes the
# files this build installed and nothing else, and asks whether the settings go too. Silently, with
# /S, they stay unless /RemoveData is given. An upgrade never asks and never removes them.

!include LogicLib.nsh

!ifdef BUILD_UNINSTALLER

!define WITTY_FILE_LIST "resources\installed-files.txt"

# Leaves "1" on the stack if this line of the list is a plain path inside the program's folder.
Function un.wittyIsPlainPath
  Exch $0
  Push $1
  Push $2
  StrCpy $1 0
  StrCpy $2 $0 1
  ${if} $0 == ""
  ${orIf} $2 == "\"
  ${orIf} $2 == "/"
    Goto bad
  ${endIf}
  loop:
    StrCpy $2 $0 2 $1
    StrCmp $2 "" good
    StrCmp $2 ".." bad
    StrCpy $2 $0 1 $1
    StrCmp $2 ":" bad
    IntOp $1 $1 + 1
    Goto loop
  good:
    StrCpy $0 "1"
    Goto done
  bad:
    StrCpy $0 "0"
  done:
    Pop $2
    Pop $1
    Exch $0
FunctionEnd

# Reads the next line of the list ($R7, a file handle) into $R6. Empty at the end of the list.
Function un.wittyNextLine
  ClearErrors
  FileRead $R7 $R6
  ${if} ${Errors}
    StrCpy $R6 ""
    Return
  ${endIf}
  StrCpy $R5 $R6 1 -1
  ${if} $R5 == "$\n"
    StrCpy $R6 $R6 -1
  ${endIf}
FunctionEnd

# Stops before anything is removed if a file is still in use, so a failure can't leave half a program.
Function un.wittyCheckNothingBusy
  FileOpen $R7 "$PLUGINSDIR\installed-files.txt" r
  loop:
    Call un.wittyNextLine
    StrCmp $R6 "" done
    StrCpy $R5 $R6 1 -1
    StrCmp $R5 "\" loop
    Push $R6
    Call un.wittyIsPlainPath
    Pop $R5
    StrCmp $R5 "1" 0 loop
    IfFileExists "$INSTDIR\$R6" 0 loop
    ClearErrors
    FileOpen $R4 "$INSTDIR\$R6" a
    ${if} ${Errors}
      FileClose $R7
      Abort "$INSTDIR\$R6 is in use. Close ${PRODUCT_NAME} and try again. Nothing was removed."
    ${endIf}
    FileClose $R4
    Goto loop
  done:
    FileClose $R7
FunctionEnd

Function un.wittyRemoveListed
  FileOpen $R7 "$PLUGINSDIR\installed-files.txt" r
  loop:
    Call un.wittyNextLine
    StrCmp $R6 "" done
    Push $R6
    Call un.wittyIsPlainPath
    Pop $R5
    StrCmp $R5 "1" 0 loop
    StrCpy $R5 $R6 1 -1
    ${if} $R5 == "\"
      StrCpy $R6 $R6 -1
      RMDir "$INSTDIR\$R6"
    ${else}
      Delete "$INSTDIR\$R6"
    ${endIf}
    Goto loop
  done:
    FileClose $R7
FunctionEnd

!endif

# The standard setup leaves a copy of itself in the account's local folder, for an auto-updater this
# app doesn't have. That's over 100 MB, in a place no uninstaller would know about.
!macro wittyRemoveStoredSetup
  ${if} $installMode == "all"
    SetShellVarContext current
  ${endIf}
  Delete "$LOCALAPPDATA\${APP_INSTALLER_STORE_FILE}"
  RMDir "$LOCALAPPDATA\${APP_PACKAGE_NAME}-updater"
  ${if} $installMode == "all"
    SetShellVarContext all
  ${endIf}
!macroend

!macro customInstall
  !insertmacro wittyRemoveStoredSetup
!macroend

# A section of its own would make the uninstaller show a page of components, so this is called from
# the end of removing files, once nothing can stop the uninstall.
!macro wittyRemoveDataIfAsked
  ${ifNot} ${isUpdated}
    # The app doesn't register these today. Removing them here means it never leaves one behind.
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${PRODUCT_NAME}"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "electron.app.${PRODUCT_NAME}"

    StrCpy $R9 "0"
    ClearErrors
    ${GetParameters} $R0
    ${GetOptions} $R0 "/RemoveData" $R1
    ${ifNot} ${Errors}
      StrCpy $R9 "1"
    ${else}
      MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 \
        "${PRODUCT_NAME} has been removed.$\r$\n$\r$\nDo you also want to delete its settings, saved sign-ins, logs and caches for this Windows account?$\r$\n$\r$\nChoose Yes to remove everything. You'd have to sign in to your servers again if you reinstall.$\r$\nChoose No to keep them.$\r$\n$\r$\nYour servers and what's on them are never touched." \
        /SD IDNO IDNO +2
      StrCpy $R9 "1"
    ${endIf}

    ${if} $R9 == "1"
      # Electron keeps these for each Windows account, wherever the program was installed.
      ${if} $installMode == "all"
        SetShellVarContext current
      ${endIf}
      RMDir /r "$APPDATA\${PRODUCT_NAME}"
      # The app's folder before it was renamed.
      RMDir /r "$APPDATA\WittyMedia"
      ${if} $installMode == "all"
        SetShellVarContext all
      ${endIf}
    ${endIf}
  ${endIf}
!macroend

# Takes the place of the standard removal, which deletes the whole folder and whatever is in it.
!macro customRemoveFiles
  ClearErrors
  CopyFiles /SILENT "$INSTDIR\${WITTY_FILE_LIST}" "$PLUGINSDIR\installed-files.txt"
  ${if} ${FileExists} "$PLUGINSDIR\installed-files.txt"
    Call un.wittyCheckNothingBusy
    Call un.wittyRemoveListed
  ${else}
    DetailPrint "The list of installed files is missing, so only the program itself was removed from $INSTDIR."
    Delete "$INSTDIR\${APP_EXECUTABLE_FILENAME}"
  ${endIf}
  ${ifNot} ${isUpdated}
    Delete "$INSTDIR\${UNINSTALL_FILENAME}"
  ${endIf}
  # Move out of the folder so it can go. It stays if someone else's files are still in it.
  SetOutPath $TEMP
  RMDir "$INSTDIR"
  ${ifNot} ${isUpdated}
    !insertmacro wittyRemoveStoredSetup
    !insertmacro wittyRemoveDataIfAsked
    # Setup makes this folder if it isn't there. It goes only if nothing else is in it.
    ${if} $installMode != "all"
      RMDir "$LOCALAPPDATA\Programs"
    ${endIf}
  ${endIf}
!macroend
