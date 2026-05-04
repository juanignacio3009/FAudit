<#
.SYNOPSIS
    Script de remediacion manual para habilitar Legacy MFA (Per-User).
.DESCRIPTION
    Toma un arreglo de correos electronicos validados manualmente y cambia su estado 
    de MFA Legacy (Per-User) de "Disabled" a "Enabled" directamente.
#>

# Forzar codificacion UTF-8
try { [console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# =========================
# SETUP Y AUTENTICACION
# =========================
$runInAzure = $false

Write-Host "[*] Autenticando en Microsoft Graph API..." -ForegroundColor Yellow
if ($runInAzure) {
    Connect-MgGraph -Identity -NoWelcome | Out-Null
} else {
    # Permisos necesarios para modificar propiedades de usuarios (Legacy MFA)
    Connect-MgGraph -Scopes @("User.ReadWrite.All")
}
Write-Host "[+] Autenticacion exitosa." -ForegroundColor Green

# =========================
# CONFIGURACION
# =========================
# ⚠️ AQUÍ PONES LOS CORREOS DE LOS USUARIOS QUE VAS A FORZAR (Ya validados por ti)
$usuariosRemediar = @(
    "ignacio.mecchia@proveedor.ues21.edu.ar"
)

# =========================
# BUCLE DE REMEDIACION
# =========================
Write-Host ' '
Write-Host "Iniciando proceso de remediacion para $($usuariosRemediar.Count) usuarios..." -ForegroundColor Cyan

foreach ($upn in $usuariosRemediar) {
    Write-Host " -> Procesando: $upn" -NoNewline
    
    try {
        # Payload para cambiar el estado de Legacy MFA a "Enabled"
        $body = @{
            strongAuthenticationRequirements = @(
                @{
                    state = "Enabled"
                }
            )
        }

        # Hacemos la peticion PATCH directamente a la API para asegurar compatibilidad universal
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$upn" -Body $body -ErrorAction Stop

        Write-Host " [MFA HABILITADO EXITOSAMENTE]" -ForegroundColor Green
    } catch {
        Write-Host " [ERROR: $($_.Exception.Message)]" -ForegroundColor Red
    }
}

Write-Host ' '
Write-Host "[*] Proceso de remediacion finalizado. Desconectando..." -ForegroundColor DarkGray
Disconnect-MgGraph