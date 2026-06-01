<#
.SYNOPSIS
    Script de notificación vía Microsoft Teams para usuarios sin MFA.
.DESCRIPTION
    Toma un arreglo de correos electrónicos, crea o recupera un chat 1-a-1
    y envía un mensaje por Teams solicitando feedback sobre la activación de MFA.
    Incluye un enlace directo al manual PDF en la nube.
#>

# Forzar codificacion UTF-8
try { [console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

Write-Host "[*] Autenticando en Microsoft Graph API..." -ForegroundColor Yellow
# Se requieren permisos Chat.ReadWrite para enviar mensajes y User.Read.All para buscar a los usuarios
Connect-MgGraph -Scopes @("User.Read.All", "Chat.ReadWrite")
Write-Host "[+] Autenticacion exitosa." -ForegroundColor Green

# 1. Obtener el ID del usuario que ejecuta el script (Remitente)
$meResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction Stop
$senderId = $meResponse.id

# =========================
# CONFIGURACION DEL MENSAJE
# =========================

# ⚠️ AQUÍ PONES LOS CORREOS DE LOS USUARIOS QUE QUIERES NOTIFICAR
$usuariosCriticos = @(
    "Veronica.Lopez@ues21.edu.ar"
    "Marcos.Charri@ues21.edu.ar"
    "julieta.murat@ues21.edu.ar"
    "david.carranza@proveedor.ues21.edu.ar"
    "Maria.Rizzi@ues21.edu.ar"
)

# ⚠️ URL del manual PDF alojado en OneDrive / SharePoint
$urlManualPDF = "https://ues21eduar-my.sharepoint.com/:b:/g/personal/ignacio_mecchia_proveedor_ues21_edu_ar/IQDou-twO24jRbiSwV91lFgYAXTXI6A4yoTMYDaosSUyYfE?e=JwqL64"

# =========================
# BUCLE DE ENVÍO DE MENSAJES (TEAMS)
# =========================
Write-Host ' '
Write-Host "Iniciando envio de mensajes por Teams a $($usuariosCriticos.Count) usuarios..." -ForegroundColor Cyan

foreach ($destinatario in $usuariosCriticos) {
    Write-Host " -> Procesando: $destinatario" -NoNewline
    
    try {
        # 2. Obtener información del destinatario
        $targetUser = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$destinatario" -ErrorAction Stop
        $targetId = $targetUser.id
        
        # Extraer correctamente el primer nombre (Prioriza 'GivenName' para evitar agarrar el Apellido)
        if (-not [string]::IsNullOrWhiteSpace($targetUser.givenName)) {
            $primerNombre = ($targetUser.givenName -split " ")[0]
        } elseif ($targetUser.displayName -match ",") {
            $primerNombre = (($targetUser.displayName -split ",")[1].Trim() -split " ")[0]
        } else {
            $primerNombre = ($targetUser.displayName -split " ")[0]
        }

        # 3. Construir el cuerpo del mensaje personalizado en HTML
        # Se usan entidades HTML (&iacute;, &oacute;, etc.) para evitar los caracteres rotos por codificacion ANSI
        $cuerpoMensaje = @"
Buen d&iacute;a <b>$primerNombre</b>!! Soy Juan Ignacio, del equipo de soporte Microsoft siglo 21, te escribo porque detectamos de que no tenes el doble factor activado en tu cuenta, &iquest;tuviste alg&uacute;n problema que recuerdes o necesitas ayuda para configurarlo?<br><br>
&#128073; <a href='$urlManualPDF'>Podes revisar el manual de configuraci&oacute;n paso a paso haciendo clic aqu&iacute;</a>.
"@

        # 4. Crear o recuperar el Chat 1-a-1
        $chatPayload = @{
            chatType = "oneOnOne"
            members = @(
                @{ "@odata.type" = "#microsoft.graph.aadUserConversationMember"; roles = @("owner"); "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$senderId')" },
                @{ "@odata.type" = "#microsoft.graph.aadUserConversationMember"; roles = @("owner"); "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$targetId')" }
            )
        }

        $chatResponse = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/chats" -Body $chatPayload -ErrorAction Stop
        $chatId = $chatResponse.id

        # 5. Enviar el mensaje al Chat
        $msgPayload = @{ body = @{ contentType = "html"; content = $cuerpoMensaje } }
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/messages" -Body $msgPayload -ErrorAction Stop
        
        Write-Host " [ENVIADO POR TEAMS]" -ForegroundColor Green
        Start-Sleep -Seconds 1 # Pequeña pausa para no saturar la API (Throttling)
    } catch {
        Write-Host " [ERROR: $_]" -ForegroundColor Red
    }
}
Write-Host "[*] Proceso finalizado. Desconectando..." -ForegroundColor DarkGray
Disconnect-MgGraph