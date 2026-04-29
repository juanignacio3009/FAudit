# 1. Pon el Object ID de tu cuenta de automatización aquí
$ManagedIdentityObjectId = "0d7a0949-918d-4241-bf14-23ca58ca5a16"

# 2. Estos son los permisos exactos que requiere tu script
$GraphScopes = @(
    "User.Read.All",
    "Directory.Read.All",
    "AuditLog.Read.All",
    "Reports.Read.All",
    "Mail.Send"
)

# 3. Te pedirá iniciar sesión con tu cuenta de administrador
Write-Host "Iniciando sesion para asignar permisos..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All", "Application.Read.All"

# 4. Buscamos a Microsoft Graph en las entrañas de tu Tenant
$GraphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# 5. Asignamos los permisos uno por uno
foreach ($Scope in $GraphScopes) {
    $AppRole = $GraphServicePrincipal.AppRoles | Where-Object { $_.Value -eq $Scope }

    if ($AppRole) {
        Write-Host "Asignando permiso: $Scope..." -ForegroundColor Cyan
        $AppRoleAssignment = @{
            principalId = $ManagedIdentityObjectId
            resourceId = $GraphServicePrincipal.Id
            appRoleId = $AppRole.Id
        }
        
        try {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityObjectId -BodyParameter $AppRoleAssignment | Out-Null
            Write-Host "[+] Permiso $Scope asignado con exito." -ForegroundColor Green
        } catch {
            Write-Host "[!] El permiso $Scope probablemente ya estaba asignado o hubo un error: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }
}

Disconnect-MgGraph
Write-Host "Proceso finalizado." -ForegroundColor White