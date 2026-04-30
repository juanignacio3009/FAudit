<#
.SYNOPSIS
    Script de notificacion manual para usuarios sin MFA (Críticos).
.DESCRIPTION
    Toma un arreglo de correos electrónicos y envía un mensaje predefinido 
    solicitando feedback sobre por qué no han activado MFA, antes de aplicar bloqueos.
#>

# Forzar codificacion UTF-8 para evitar caracteres extraños en la consola
try { [console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# =========================
# SETUP Y AUTENTICACION
# =========================
$runInAzure = $false # Cambiar a $true si decides ejecutarlo desde Azure Automation

Write-Host "[*] Autenticando en Microsoft Graph API..." -ForegroundColor Yellow
if ($runInAzure) {
    Connect-MgGraph -Identity -NoWelcome | Out-Null
} else {
    Connect-MgGraph -Scopes @("Mail.Send")
}
Write-Host "[+] Autenticacion exitosa." -ForegroundColor Green

# =========================
# CONFIGURACION DEL MENSAJE
# =========================
$emailRemitente = "ignacio.mecchia@proveedor.ues21.edu.ar"
$asunto = "Accion Requerida: Configuracion de Autenticacion Multifactor (MFA)"

# ⚠️ AQUÍ PONES LOS CORREOS DE LOS USUARIOS QUE QUIERES NOTIFICAR
$usuariosCriticos = @(
    "juanignaciomecchia@gmail.com"
)

$cuerpoMensaje = @"
<html>
<body style="font-family: Arial, sans-serif; color: #333;">
    <p>Hola,</p>
    <p>Desde el equipo de Seguridad Inform&aacute;tica de Siglo 21 nos comunicamos porque hemos detectado que tu cuenta institucional a&uacute;n no tiene configurada la <b>Autenticaci&oacute;n Multifactor (MFA)</b>.</p>
    <p>Para proteger la informaci&oacute;n de la instituci&oacute;n, en las pr&oacute;ximas semanas ser&aacute; obligatorio el uso de MFA para todos los usuarios al iniciar sesi&oacute;n.</p>
    <p>Antes de aplicar esta pol&iacute;tica y para evitar que tu cuenta quede bloqueada, queremos asegurarnos de que no tengas ning&uacute;n impedimento t&eacute;cnico.</p>
    <p><b>Por favor, responde a este correo inform&aacute;ndonos:</b></p>
    <ul>
        <li>Si necesitas asistencia t&eacute;cnica para configurarlo.</li>
        <li>Si existe alg&uacute;n motivo o limitaci&oacute;n (ej. robo, extrav&iacute;os, pol&iacute;tica especial) que te impida utilizar MFA.</li>
    </ul>
    <p>Agradecemos tu colaboraci&oacute;n para mantener nuestra red segura.</p>
    <br>
    <p><i>Equipo de Soporte / Seguridad Inform&aacute;tica de la Universidad Siglo 21</i></p>
</body>
</html>
"@

# =========================
# BUCLE DE ENVÍO DE CORREOS
# =========================
Write-Host ' '
Write-Host "Iniciando envio de correos a $($usuariosCriticos.Count) usuarios criticos..." -ForegroundColor Cyan

foreach ($destinatario in $usuariosCriticos) {
    Write-Host " -> Procesando: $destinatario" -NoNewline
    
    $mailBody = @{
        message = @{
            subject = $asunto
            body = @{
                contentType = "HTML"
                content = $cuerpoMensaje
            }
            toRecipients = @(
                @{ emailAddress = @{ address = $destinatario } }
            )
        }
        saveToSentItems = "true" # Guarda una copia en los 'Elementos Enviados' del remitente
    }

    try {
        $endpointUri = if ($runInAzure) { "https://graph.microsoft.com/v1.0/users/$emailRemitente/sendMail" } else { "https://graph.microsoft.com/v1.0/me/sendMail" }
        Invoke-MgGraphRequest -Method POST -Uri $endpointUri -Body $mailBody -ErrorAction Stop
        Write-Host " [ENVIADO]" -ForegroundColor Green
    } catch {
        Write-Host " [ERROR: $_]" -ForegroundColor Red
    }
}

Write-Host ' '
Write-Host "[*] Proceso de notificacion finalizado. Desconectando..." -ForegroundColor DarkGray
Disconnect-MgGraph