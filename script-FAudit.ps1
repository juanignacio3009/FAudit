<#
  _____ _             _ _ _           ____    ___  
 |  ___/ \  _   _  __| (_) |_  __   _|___ \  / _ \ 
 | |_ / _ \| | | |/ _` | | __| \ \ / / __) || | | |
 |  _/ ___ \ |_| | (_| | | |_   \ V / / __/ | |_| |
 |_|/_/   \_\__,_|\__,_|_|\__|   \_/ |_____(_)___/ 
                                                   
.SYNOPSIS
    Auditoria avanzada de MFA en Entra ID.
.DESCRIPTION
    Descarga y cruza informacion de usuarios, metodos de autenticacion registrados
    y logs de inicio de sesion (30 dias) para determinar la postura real de MFA,
    filtrando el ruido de cuentas de servicio mediante expresiones regulares.
    Exporta resultados a CSV y construye un Dashboard estable en Excel.
#>

# Forzar codificacion UTF-8 en la consola para evitar caracteres extraños (mojibake)
try { [console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# Desactivar barra de progreso en la nube para evitar congelamientos
if ($runInAzure) { $ProgressPreference = 'SilentlyContinue' }

try { Clear-Host } catch {}
Write-Host ' '
Write-Host '  _____ _             _ _ _           ____    ___  ' -ForegroundColor Cyan
Write-Host ' |  ___/ \  _   _  __| (_) |_  __   _|___ \  / _ \ ' -ForegroundColor Cyan
Write-Host ' | |_ / _ \| | | |/ _` | | __| \ \ / / __) || | | |' -ForegroundColor Cyan
Write-Host ' |  _/ ___ \ |_| | (_| | | |_   \ V / / __/ | |_| |' -ForegroundColor Cyan
Write-Host ' |_|/_/   \_\__,_|\__,_|_|\__|   \_/ |_____(_)___/ ' -ForegroundColor Cyan
Write-Host "                                                   "
Write-Host "         A U D I T O R I A   D E   M F A           " -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ' '
Write-Host " Iniciando proceso de auditoria..." -ForegroundColor Gray
Write-Host ' '

# =========================
# SETUP Y AUTENTICACION
# =========================
$runInAzure = $true # Cambiar a $true cuando lo ejecutes en Azure Automation

$scopes = @(
    "User.Read.All",
    "Directory.Read.All",
    "AuditLog.Read.All",
    "Reports.Read.All"
)
Write-Host "[*] Autenticando en Microsoft Graph API..." -ForegroundColor Yellow
if ($runInAzure) {
    Connect-MgGraph -Identity -NoWelcome | Out-Null
} else {
    Connect-MgGraph -Scopes $scopes
}
Write-Host "[+] Autenticacion exitosa." -ForegroundColor Green

# =========================
# CONFIGURACION GENERAL
# =========================
$fecha = Get-Date -Format "yyyy-MM-dd_HH-mm"

# Adaptacion para la nube: Usar carpeta temporal si estamos en Azure
if ($runInAzure) {
    $ruta = "$env:TEMP\reportes"
    $rutaPlantilla = "$env:TEMP\plantilla_dashboard.xlsx"
    
    # Descargar la plantilla directamente desde tu repositorio de GitHub
    $urlPlantilla = "https://raw.githubusercontent.com/juanignacio3009/FAudit/main/plantilla_dashboard.xlsx"
    try {
        Invoke-WebRequest -Uri $urlPlantilla -OutFile $rutaPlantilla -UseBasicParsing
        Write-Host "  -> Plantilla visual descargada desde GitHub." -ForegroundColor DarkGray
    } catch {
        Write-Host "  -> No se encontro la plantilla en GitHub. Se usara formato por defecto." -ForegroundColor DarkGray
    }
} else {
    $ruta = ".\reportes"
    $rutaPlantilla = ".\plantilla_dashboard.xlsx"
}

$rutaCsv = "$ruta\mfa_auditoria_$fecha.csv"
$rutaExcel = "$ruta\mfa_auditoria_$fecha.xlsx"
$diasLogs = 30

# Configuracion de Correo Electronico
$enviarCorreo = $true
$emailRemitente = "ignacio.mecchia@proveedor.ues21.edu.ar"   # Cambiar por un buzon valido en Microsoft 365
$emailDestinatario = "juanignaciomecchia@gmail.com" # Quien recibe el reporte

# Clasificacion de cuentas de servicio / genericas (Noise Reduction)
$clasificarCuentasServicio = $true
$patronesExcluidos = @(
    # 1. Administradores, Pruebas y Auditoria
    "^admin", "^prueba", "^test", "^auditoria", "^seginfo", "^Laura.Rosso", "^Belen.Mende", "^JuanCarlos.Rabbat", "^Jefedeturno",

    # 2. Infraestructura, Aulas, Laboratorios y Salas
    "^arccpc", "^ncaula", "^nclab", "^nclcd", "^ncpar", "^nctotem", "^ncplayer",
    "^rcaula", "^rclab", "^rclcd", "^vl-lab", "^vlaula", "^sala", "^ws\d", "^wsauto",
    "^hibrida", "^vr\d", "^cctablet", "^ccarcor", "^campus-", "^tv\.",

    # 3. Cuentas de Servicio, Sincronizacion y Sistemas Internos
    "^sync_", "^svc_", "^srv_", "^iwam_", "^iusr_", "_vmware", "^klnagsvc", "^ldap",
    "^veeam", "^jira", "^gitlab", "^kronos", "^passbolt", "^zabbix", "^rundeck",
    "^adaudit", "^macsoporte", "^bot", "^siem", "^chassisflex", "^arcgis",

    # 4. Integraciones, Analitica, Bots y Reportes
    "^chatgpt", "^powerbi", "^power_bi", "^bpm", "^zoom", "^calipso", "^facturador",
    "^integracion", "^monitoreo", "^monitor", "^report", "^notificacion", "^notif",
    "^digitalizacion", "^navegacion", "^alerta",

    # 5. Buzones Compartidos Genericos y Departamentos
    "^soporte", "^info", "^gestion", "^seguridad", "^reservas", "^asistencia",
    "^posgrado", "^rrii", "^biblioteca", "^egresados", "^comunicado", "^encuestas",
    "^tickets", "^admision", "^consultas", "^centro", "^od\.", "^mesa\.ayuda",
    "^recepcion", "^sum\d*@", "^secretaria", "^presidencia", "^vicepresidencia"
)

New-Item -ItemType Directory -Path $ruta -Force | Out-Null

# =========================
# EXTRACCION DE DATOS
# =========================
Write-Host ' '
Write-Host "[*] Obteniendo usuarios corporativos..." -ForegroundColor Yellow
# Filtramos userType eq 'Member' para ignorar cuentas Guest/Externas
$users = Get-MgUser -All -Filter "userType eq 'Member'" -Property Id,DisplayName,UserPrincipalName,AccountEnabled

Write-Host "[+] Usuarios obtenidos: $($users.Count)" -ForegroundColor Green

Write-Host "[*] Obteniendo reportes de registro MFA..." -ForegroundColor Yellow
$mfaReport = Invoke-MgGraphRequest -Method GET `
-Uri "https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails"

$mfaHash = @{}
foreach ($u in $mfaReport.value) {
    if ($u.userPrincipalName) {
        $mfaHash[$u.userPrincipalName.ToLower().Trim()] = $u
    }
}
Write-Host "[+] Reportes MFA procesados." -ForegroundColor Green

Write-Host "[*] Obteniendo logs de inicio de sesion (ultimos $diasLogs dias)..." -ForegroundColor Yellow

$fechaFiltro = (Get-Date).AddDays(-$diasLogs).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Corrección: Usamos el endpoint 'beta' en lugar de 'v1.0' porque el parser OData de v1.0 no soporta hacer $select sobre 'authenticationRequirement'
# Esto mantiene la descarga ultra rápida sin arrojar el error "BadRequest".
$uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=createdDateTime ge $fechaFiltro and status/errorCode eq 0&`$top=1000&`$select=id,userPrincipalName,authenticationRequirement"

$logs = [System.Collections.Generic.List[PSObject]]::new()
$page = 1

while ($uri) {

    Write-Host "  -> Descargando pagina $page..." -ForegroundColor DarkGray
    $retryCount = 0
    $success = $false

    while (-not $success -and $retryCount -lt 3) {
        try {
            $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop

            if ($response.value) {
                foreach ($item in $response.value) {
                    $logs.Add($item)
                }
            }

            $uri = $response.'@odata.nextLink'
            $page++
            $success = $true

            Start-Sleep -Milliseconds 200
        } catch {
            $retryCount++
            Write-Host "Error en pagina $page (Intento $retryCount de 3)" -ForegroundColor Yellow
            Write-Host "Detalle del error: $_" -ForegroundColor Red
            Start-Sleep 2
        }
    }

    if (-not $success) {
        Write-Host "Se fallo 3 veces seguidas. Abortando descarga de logs restantes." -ForegroundColor Red
        break
    }
}

Write-Host "[+] Total logs descargados: $($logs.Count)" -ForegroundColor Green

# =========================
# TRANSFORMACION (NORMALIZACION)
# =========================
Write-Host ' '
Write-Host "[*] Normalizando e indexando logs para busqueda rapida..." -ForegroundColor Yellow
$logsGrouped = $logs | Where-Object userPrincipalName | ForEach-Object {
    $_ | Add-Member -NotePropertyName UPN_Normalized `
        -NotePropertyValue ($_.userPrincipalName.ToLower().Trim()) -PassThru
} | Group-Object UPN_Normalized

$logsHash = @{}
foreach ($group in $logsGrouped) {
    $logsHash[$group.Name] = $group.Group
}

# =========================
# ANALISIS Y CLASIFICACION
# =========================
Write-Host ' '
Write-Host "[*] Analizando matriz de usuarios vs logs..." -ForegroundColor Yellow

$resultado = [System.Collections.Generic.List[PSObject]]::new()
$total = $users.Count

try {
    $i = 0
    foreach ($user in $users) {
        $i++

        # Progreso Visual
        if ($i % 10 -eq 0 -or $i -eq $total) {
            $porcentaje = [math]::Round(($i / $total) * 100, 2)
            Write-Progress -Activity "Analizando Usuarios MFA" -Status "Procesando $i de $total ($porcentaje%)" -PercentComplete $porcentaje
        }

        if (-not $user.AccountEnabled) { continue }

        $upn = $user.UserPrincipalName.ToLower().Trim()

        $tipoCuenta = "Humano"
        if ($clasificarCuentasServicio) {
            foreach ($patron in $patronesExcluidos) {
                if ($upn -match $patron) { 
                    $tipoCuenta = "Servicio"
                    break 
                }
            }
        }

        $mfa = $mfaHash[$upn]

        $registered = $false
        $capable = $false

        if ($mfa) {
            $registered = $mfa.isMfaRegistered
            $capable = $mfa.isMfaCapable
        }

        # Busqueda O(1) usando la hashtable (Ultra rápido)
        $userLogs = $logsHash[$upn]

        $loginConMFA = $false
        $loginSinMFA = $false

        if ($userLogs) {
            foreach ($log in $userLogs) {
                $auth = $log.authenticationRequirement

                if ($auth -in @("multiFactorAuthentication","previouslySatisfied")) {
                    $loginConMFA = $true
                }

                if ($auth -in @("singleFactorAuthentication","password")) {
                    $loginSinMFA = $true
                }
            }
        }

        # =========================
        # CLASIFICACION REAL
        # =========================
        if (-not $userLogs) {
            $estado = "SIN_ACTIVIDAD"
        }
        elseif ($loginConMFA) {
            $estado = "SEGURO"
        }
        elseif ($loginSinMFA) {
            $estado = "CRITICO"
        } else {
            $estado = "REVISAR" # Fallback visual por si hay combinaciones extranas
        }

        $resultado.Add([PSCustomObject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Tipo              = $tipoCuenta
            MFARegistered     = $registered
            MFACapable        = $capable
            LoginConMFA       = $loginConMFA
            LoginSinMFA       = $loginSinMFA
            Estado            = $estado
        })
    }
} finally {
    Write-Progress -Activity "Analizando Usuarios MFA" -Completed

    # =========================
    # EXPORTACION Y DASHBOARD
    # =========================
    Write-Host ' '
    Write-Host "[*] Exportando resultados a CSV..." -ForegroundColor Yellow
    $resultado | Export-Csv $rutaCsv -NoTypeInformation -Encoding UTF8

    Write-Host "[*] Generando Dashboard en Excel..." -ForegroundColor Yellow
    try {
        $humanos = $resultado | Where-Object { $_.Tipo -eq "Humano" }
        $totalServicio = ($resultado | Where-Object { $_.Tipo -eq "Servicio" }).Count

        $totalUsers = $humanos.Count
        $criticos = ($humanos | Where-Object { $_.Estado -eq "CRITICO" }).Count
        $seguros = ($humanos | Where-Object { $_.Estado -eq "SEGURO" }).Count
        $sinActividad = ($humanos | Where-Object { $_.Estado -eq "SIN_ACTIVIDAD" }).Count
        $revisar = ($humanos | Where-Object { $_.Estado -eq "REVISAR" }).Count

        $score = 0
        if ($totalUsers -gt 0) {
            $score = [math]::Round(($seguros / $totalUsers) * 100, 2)
        }

        $condCritico = New-ConditionalText -Text "CRITICO" -BackgroundColor Red -ConditionalTextColor White
        $condSeguro  = New-ConditionalText -Text "SEGURO" -BackgroundColor DarkGreen -ConditionalTextColor White
        $condSinAct  = New-ConditionalText -Text "SIN_ACTIVIDAD" -BackgroundColor Gray -ConditionalTextColor White

        # Logica de Plantilla Base
        $usarPlantilla = Test-Path $rutaPlantilla
        if ($usarPlantilla) {
            Write-Host "  -> Utilizando plantilla base para el Dashboard..." -ForegroundColor DarkGray
            Copy-Item -Path $rutaPlantilla -Destination $rutaExcel -Force
        }

        $resultado | Export-Excel -Path $rutaExcel -AutoSize -TableName "DatosAuditoria" -TableStyle Medium2 -WorksheetName "MFA_Report" -ConditionalText $condCritico, $condSeguro, $condSinAct -ClearSheet

        $excelPackage = Open-ExcelPackage -Path $rutaExcel
        $dashboardSheet = $excelPackage.Workbook.Worksheets["Dashboard"]
        if ($null -eq $dashboardSheet) {
            $dashboardSheet = $excelPackage.Workbook.Worksheets.Add("Dashboard")
        }

        if ($usarPlantilla) {
            # Modo Plantilla: Solo inyectamos los numeros crudos en las celdas de valores.
            # Se respetan las filas 6, 9, 10 y 11 porque contienen formulas propias de Excel.
            $dashboardSheet.Cells["C2"].Value = $totalUsers
            $dashboardSheet.Cells["C3"].Value = $seguros
            $dashboardSheet.Cells["C4"].Value = $criticos
            $dashboardSheet.Cells["C6"].Value = $sinActividad
            $dashboardSheet.Cells["C7"].Value = $revisar
            $dashboardSheet.Cells["C12"].Value = $totalServicio
        } else {
            # Modo Por Defecto: Se crea la tabla desde cero si no existe la plantilla
            $dashboardSheet.Cells["B1"].Value = "Resumen General"
            $dashboardSheet.Cells["B1"].Style.Font.Bold = $true
            $dashboardSheet.Cells["B1"].Style.Font.Size = 14

            $dashboardSheet.Cells["B2"].Value = "Usuarios Humanos Analizados:"
            $dashboardSheet.Cells["B3"].Value = "Usuarios Seguros (MFA):"
            $dashboardSheet.Cells["B4"].Value = "Usuarios Criticos (Sin MFA):"
            $dashboardSheet.Cells["B5"].Value = "Usuarios Sin Actividad:"
            $dashboardSheet.Cells["B8"].Value = "Usuarios a Revisar:"
            $dashboardSheet.Cells["B9"].Value = "SCORE REAL (Cumplimiento):"
            $dashboardSheet.Cells["B10"].Style.Font.Bold = $true
            $dashboardSheet.Cells["B11"].Value = "Cuentas de Servicio (Excluidas del Score):"
            $dashboardSheet.Cells["B11"].Style.Font.Italic = $true

            $dashboardSheet.Cells["C2"].Value = $totalUsers
            $dashboardSheet.Cells["C3"].Value = $seguros
            $dashboardSheet.Cells["C4"].Value = $criticos
            $dashboardSheet.Cells["C5"].Value = $sinActividad
            $dashboardSheet.Cells["C8"].Value = $revisar
            $dashboardSheet.Cells["C10"].Value = "$score %"
            $dashboardSheet.Cells["C10"].Style.Font.Bold = $true
            $dashboardSheet.Cells["C11"].Value = $totalServicio
            $dashboardSheet.Cells["C11"].Style.Font.Italic = $true

            $dashboardSheet.Cells["B:C"].AutoFitColumns()
        }
        Close-ExcelPackage $excelPackage

        Write-Host "[+] Excel generado correctamente." -ForegroundColor Green
    } catch {
        Write-Host "[!] Advertencia: El Excel base se genero, pero fallo la creacion del Dashboard." -ForegroundColor Yellow
        Write-Host "    Detalle del error: $_" -ForegroundColor Red
    }

    # Imprimir metricas en la consola al final
    Write-Host ' '
    Write-Host '+=====================================================+' -ForegroundColor Cyan
    Write-Host '|              R E S U M E N   F I N A L              |' -ForegroundColor Cyan
    Write-Host '+=====================================================+' -ForegroundColor Cyan
    Write-Host "  Usuarios Humanos analizados : $totalUsers"
    Write-Host "  Usuarios Seguros          : $seguros" -ForegroundColor Green
    Write-Host "  Usuarios Criticos         : $criticos" -ForegroundColor Red
    Write-Host "  Sin actividad / Revisar   : $($sinActividad + $revisar)" -ForegroundColor DarkGray
    Write-Host '+-----------------------------------------------------+' -ForegroundColor Cyan
    Write-Host "  SCORE REAL (Cumplimiento) : $score %" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "  Cuentas de Servicio (Omitidas del Score): $totalServicio" -ForegroundColor Gray
    Write-Host '+=====================================================+' -ForegroundColor Cyan
    Write-Host "Archivos generados en: $(Resolve-Path $ruta)" -ForegroundColor Gray

    # =========================
    # ENVIO DE CORREO ELECTRONICO
    # =========================
    if ($enviarCorreo -and (Test-Path $rutaExcel)) {
        Write-Host ' '
        Write-Host "[*] Preparando envio de correo electronico..." -ForegroundColor Yellow
        try {
            $fileBytes = [System.IO.File]::ReadAllBytes($rutaExcel)
            $fileBase64 = [System.Convert]::ToBase64String($fileBytes)

            $mailBody = @{
                message = @{
                    subject = "Reporte de Auditoria MFA - $fecha"
                    body = @{
                        contentType = "HTML"
                        content = "Hola,<br><br>Se ha generado el reporte automatizado de auditoria de MFA.<br><br><b>Score Real de Cumplimiento: $score %</b><br><br>Encuentra el detalle completo en el Excel adjunto.<br><br><i>Generado por FAudit.</i>"
                    }
                    toRecipients = @(
                        @{ emailAddress = @{ address = $emailDestinatario } }
                    )
                    attachments = @(
                        @{
                            "@odata.type" = "#microsoft.graph.fileAttachment"
                            name = "mfa_auditoria_$fecha.xlsx"
                            contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                            contentBytes = $fileBase64
                        }
                    )
                }
                saveToSentItems = "false"
            }

            # Logica de envio hibrida (Local vs Nube)
            if ($runInAzure) {
                $endpointUri = "https://graph.microsoft.com/v1.0/users/$emailRemitente/sendMail"
            } else {
                $endpointUri = "https://graph.microsoft.com/v1.0/me/sendMail"
            }

            Invoke-MgGraphRequest -Method POST -Uri $endpointUri -Body $mailBody -ErrorAction Stop
            Write-Host "[+] Reporte enviado exitosamente a $emailDestinatario" -ForegroundColor Green
        } catch {
            Write-Host "[!] Error al enviar el correo electronico: $_" -ForegroundColor Red
        }
    }
}

Write-Host ' '
Write-Host '[*] Desconectando de Microsoft Graph...' -ForegroundColor DarkGray
Disconnect-MgGraph