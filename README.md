# 🛡️ Auditoría MFA - "FAudit"

**Versión Actual:** 2.0.6 *(Suite Completa: Auditoría, Notificación y Remediación)*

---

## 1. Objetivo y Explicación

Este script analiza la postura real de seguridad (MFA) de todos los usuarios "Miembros" de Microsoft Entra ID.
A diferencia de los reportes estáticos del portal, este programa cruza múltiples fuentes de datos en tiempo real:

- Estado de la cuenta (Habilitada/Deshabilitada)
- Registro de métodos MFA (Microsoft Authenticator, SMS, Hardware Keys, etc.)
- Logs de inicio de sesión (Sign-Ins) de los últimos 30 días
- Tipo de cuenta (Clasificación Humano vs Servicio mediante Regex)

Con esta información, clasifica a cada usuario en uno de los siguientes estados reales:

- 🟢 **SEGURO:** El usuario inició sesión exitosamente validando MFA en el periodo evaluado.
- 🔴 **CRÍTICO:** El usuario inició sesión únicamente con contraseña (SFA) burlando la seguridad.
- ⚪ **SIN_ACTIVIDAD:** El usuario no tiene registros de inicio de sesión interactivos en los últimos 30 días.
- 🟡 **REVISAR:** El usuario tiene patrones de log anómalos que requieren revisión manual.

> **Nota sobre Cuentas de Servicio:** El script evalúa y exporta a todas las cuentas para tener un registro histórico completo. Sin embargo, etiqueta a las cuentas institucionales/aulas/laboratorios como "Servicio" y las excluye del cálculo matemático final para no contaminar el Score Real.

## 2. Cómo Funciona (Flujo Técnico)

1. **Preparación:** Fuerza la consola de PowerShell a codificación UTF-8 para evitar errores visuales (mojibake) y se conecta a MS Graph API.
2. **Recolección de Usuarios:** Obtiene únicamente cuentas corporativas reales filtrando por `userType eq 'Member'`.
3. **Descarga de Logs (Motor Optimizado):** 
   - Consulta el endpoint `beta` para permitir el uso de `$select` sobre el campo de autenticación (evitando un bug conocido de OData en v1.0).
   - Descarga el historial de 30 días con un sistema de 3 reintentos por página ante caídas de red.
   - Almacena decenas de miles de logs en listas genéricas de .NET (`List[PSObject]`), evitando el colapso de memoria.
4. **Normalización:** Indexa los logs en una *Hashtable* (Diccionario) para que la búsqueda por UPN sea de complejidad `O(1)` (instantánea).
5. **Análisis:** Evalúa la lógica de autenticación (priorizando los éxitos de MFA para evitar falsos positivos por refrescos de tokens SFA en segundo plano).
6. **Exportación Segura (Safe-Exit):** Todo el proceso está envuelto en un bloque `try...finally`. Si el operador cancela el script manualmente (`Ctrl+C`), el programa intercepta la orden y exporta lo analizado hasta ese instante.
   - Genera un archivo CSV histórico.
   - Genera un archivo Excel (`.xlsx`) profesional con:
     * **Pestaña 'MFA_Report':** Tabla de datos con filtros, auto-ajuste, columna "Tipo" y formato condicional (Rojo/Verde/Gris).
     * **Pestaña 'Dashboard':** Resumen ejecutivo con métricas y el "Score Real" (calculado exclusivamente sobre los usuarios "Humanos").
   - **Plantillas Visuales:** Si el script detecta un archivo `plantilla_dashboard.xlsx` en el directorio raíz, lo utiliza como base. En la nube (Azure Automation), descarga la plantilla en tiempo real desde GitHub para superar la restricción de sincronización de archivos binarios.
   - **Integración Cloud:** Detecta el entorno de ejecución. Si se encuentra en Azure Automation, guarda los archivos en la memoria temporal y envía el reporte final mediante correo electrónico a través de Microsoft Graph.

## 3. Historial de Cambios y Optimizaciones

- ✔️ **Optimización Extrema (O(1)):** Uso de Hashtables y Listas Genéricas. Reducción del tiempo de ejecución de horas a segundos.
- ✔️ **Prevención de Mojibake:** Codificación UTF-8 forzada en consola y archivos de salida.
- ✔️ **Limpieza CA:** Eliminación de la lógica de Conditional Access para Tenants que no utilizan esta característica, acelerando el procesamiento.
- ✔️ **Noise Reduction:** Incorporación de expresiones regulares (Regex) para identificar instantáneamente aulas, labs y cuentas de integración.
- ✔️ **Dashboard Anti-Corrupción:** Creación de hoja de resumen mediante inyección directa de celdas (sin XML de PivotTables ni Gráficos 3D), garantizando que el Excel abra siempre de forma ultra rápida y sin advertencias de recuperación en cualquier versión de Office.
- ✔️ **Cloud & Email:** Integración con Managed Identities (`-Identity`) para logueo desatendido en Azure y envío de correo con payload de Microsoft Graph API.
- ✔️ **Template Engine:** Integración con archivos base para preservar gráficos generados manualmente sin riesgo de corrupción XML.
- ✔️ **Sincronización GitHub:** Capacidad de descargar recursos binarios (Excel templates) directamente desde un repositorio remoto durante ejecuciones desatendidas.
- ✔️ **Optimización UI Cloud:** Supresión inteligente de `Write-Progress` y comandos de consola (`Clear-Host`) al detectar ejecución en Azure para evitar colapsos de memoria y errores en hosts sin interacción.
- ✔️ **Módulo de Notificación:** Script complementario (`FANotify`) para envío de correos solicitando feedback a usuarios críticos con soporte seguro UTF-8/HTML.
- ✔️ **Módulo de Remediación:** Script complementario (`FARemediate`) para forzar la activación de Legacy MFA (Per-User MFA) de "Disabled" a "Enabled" vía Microsoft Graph.

## 4. Recomendaciones de Uso e Implementación

- **Flujo de Trabajo (Ciberseguridad Madura):** 1. Auditar (`FAudit`) -> 2. Notificar a los críticos (`FANotify`) -> 3. Forzar activación a quienes no respondan (`FARemediate`).
- **Ventana de Auditoría:** Mantener la variable `$diasLogs = 30` para asegurar una "ventana móvil" precisa que evalúe un ciclo de negocio mensual completo.
- **Requisitos Previos:** El entorno local donde corra el script debe tener instalado el módulo de exportación ejecutando: 

```powershell
Install-Module ImportExcel -Scope CurrentUser
```