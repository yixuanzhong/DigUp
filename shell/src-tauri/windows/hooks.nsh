; DigUp's additions to Tauri's NSIS installer (tauri.windows.conf.json). Tauri's uninstaller already removes the app's
; files, its Start menu entry and its Open at Sign-In value (login.rs). The helper keeps the model and the index in
; %LOCALAPPDATA%\DigUp (AppPaths in the engine), which its "Delete the application data" box doesn't know about: they
; go too when that box is checked, never on an update.
!macro NSIS_HOOK_POSTUNINSTALL
  ${If} $DeleteAppDataCheckboxState = 1
  ${AndIf} $UpdateMode <> 1
    RmDir /r "$LOCALAPPDATA\DigUp\index"
    RmDir /r "$LOCALAPPDATA\DigUp\Models"
    RmDir "$LOCALAPPDATA\DigUp"
  ${EndIf}
!macroend
