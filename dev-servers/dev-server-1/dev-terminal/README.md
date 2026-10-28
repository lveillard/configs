# Dev Sessions

Abre **Dev Sessions** desde el escritorio o el menÃº Inicio de Windows. TambiÃ©n puedes ejecutar `dev-sessions`.

El selector muestra las terminales que siguen en dev-server-1: **En uso** significa que tienen un cliente conectado; **En segundo plano**, que puedes retomarlas. **Nueva terminal** o **Ctrl+N** permite elegir proyecto/worktree, herramienta y nombre en tres pasos. El panel de detalles muestra los procesos y sus carpetas. **Ctrl+R** actualiza la lista. Puedes buscar escribiendo o abrir con doble clic.

La barra inferior deja visibles los atajos mientras aprendes. Pulsa **Ctrl+B**, suelta ambas teclas y pulsa la acciÃ³n: la barra cambia de color y muestra **AHORA pulsa**. **Esc** cancela ese prefijo. Ctrl por sÃ­ solo no envÃ­a una tecla a tmux. **F1** muestra la ayuda; dentro de una terminal abre un menÃº de acciones que puedes usar con letras, flechas o ratÃ³n. TambiÃ©n puedes hacer clic en **F1 Ayuda** en la barra.

| AcciÃ³n | Teclas o comando |
| --- | --- |
| Ver las sesiones desde cualquier terminal remota | `dev` |
| Ayuda visible / menÃº de acciones | `F1` o clic en **F1 Ayuda** |
| Ayuda desde la shell | `dev help` |
| Crear / actualizar desde el selector | `Ctrl+N` / `Ctrl+R` |
| Ver sesiones y ventanas dentro de tmux | `Ctrl+b`, despuÃ©s `s` |
| Volver al selector sin detener el proceso | `Ctrl+b`, despuÃ©s `d` |
| Abrir el selector como ventana flotante dentro de tmux | `F12` o `Ctrl+b`, despuÃ©s `m` |
| Crear otra ventana en la carpeta actual | `Ctrl+b`, despuÃ©s `c` |
| Ventana siguiente/anterior | `Ctrl+b`, despuÃ©s `n` / `p` |
| Panel a la derecha / debajo | `Ctrl+b`, despuÃ©s `v` / `h` (tambiÃ©n `%` / `"`) |
| Cambiar de panel | `Ctrl+b`, despuÃ©s una flecha, o clic en el panel |
| Ampliar / restaurar el panel | `Ctrl+b`, despuÃ©s `z` |
| Renombrar la sesiÃ³n | `Ctrl+b`, despuÃ©s `r` |
| Cancelar el prefijo | `Esc` despuÃ©s de `Ctrl+b` |
| Preguntas de Codex, reenviar Alt+Arriba | `Ctrl+Shift+Q` |
| Listar sesiones desde un script | `dev list` |

Puedes cerrar WezTerm o apagar Windows: los procesos siguen en la VM. Si apagas/reinicias la VM, los procesos en memoria terminan. Los historiales que cada CLI haya guardado se pueden reabrir con su funciÃ³n de resume. `exit` cierra esa shell; desconectar con `Ctrl+b d` la conserva.

## CLI y perfiles

InstalaciÃ³n del 18-09-2026, versiones estables actuales:

| CLI | VersiÃ³n | Alias |
| --- | --- | --- |
| Claude Code | 2.1.276 | `claude`, `claude-work`, `claude-personal`, `claude-secondary` |
| Claude / Bedrock | misma | `claude-api`, `claude-api-global`, `claude-api-eu2`, `claude-api-global-eu2`, `claude-api-sonnet` |
| Codex | 0.155.0 | `codex`, `codex-work`, `codex-personal`, `codex-api` |
| Pi | 1.3.0 | `pi`, `pi-plus` |
| Pi Plus Jev | 0.85.1 (sin actualizar) | `pi-plus-jev` |
| Devin | 3000.10.31 | `devin` |
| Grok | 1.0.34 | `grok`, `grok-api`, `grok-qwen` |
| Gemini | 0.60.0 | `gemini` |

`codex-api --profile sol` / `terra` / `luna` selecciona esas variantes; Astra es la predeterminada. `claude-api --pool eu1|global-eu1|eu2|global-eu2` conserva los pools locales.

Pi incluye pi-mcp-adapter, pi-web-access y pi-subagents. Pi Plus aÃ±ade la extensiÃ³n local Ledger; Plus Jev aÃ±ade tu extensiÃ³n de compactaciÃ³n Jev y su clave, y se queda en 0.85.1 porque no aportÃ³ valor. Son copias del cÃ³digo local al instalar, no una sincronizaciÃ³n continua: vuelve a ejecutar el instalador para refrescarlas. Pi y Pi Plus comparten el directorio de sesiones, como en Windows; Plus Jev tiene el suyo. `deepseek-flash` es el id del catÃ¡logo en 1.3.0; `deepseek-v4-pro` sigue bloqueado por el guard del perfil.

## Login manual

Ejecuta estos comandos en una shell de Dev Sessions. Cada cuenta se autentica por separado:

```sh
dev-login codex
dev-login codex-work
dev-login codex-personal
dev-login claude
dev-login claude-work
dev-login claude-personal
dev-login claude-secondary
dev-login grok
dev-login devin
dev-login gemini
dev-login bedrock
```

Codex y Grok muestran un cÃ³digo de dispositivo. Devin usa el flujo manual para terminales remotas. AWS/Bedrock muestra una URL y pide pegar el cÃ³digo que devuelva el navegador; ese Ãºnico login habilita todos los alias `claude-api*`.


## Shell y archivos

Las terminales del selector usan zsh con Starship, autocompletado, sugerencias, resaltado y bÃºsqueda del historial con `Ctrl+r`. Los alias `ll`, `la`, `g`, `gs`, `gd`, `gl` y `sessions` estÃ¡n disponibles.

- VM: `~/.config/dev-terminal/` contiene el gestor, tmux y zsh.
- VM: `~/.config/dev-profiles/` contiene los perfiles; `secrets.json` solo es legible por tu usuario y las claves se cargan Ãºnicamente al ejecutar su alias.
- VM: `~/.local/share/dev-tools/` contiene las herramientas y las extensiones copiadas.
- Windows: esta carpeta contiene la configuraciÃ³n del acceso **Dev Sessions**.

El socket de tmux es `dev-sessions`; no comparte servidor con otros usos de tmux. El acceso reutiliza la comprobaciÃ³n de conectividad de WezTerm Remote, incluida la actualizaciÃ³n de tu IP permitida al cambiar de conexiÃ³n/VPN. Si cortas la VPN durante una conexiÃ³n SSH, quizÃ¡ debas volver a abrir el acceso; las sesiones remotas siguen vivas. No requiere Tailscale.
