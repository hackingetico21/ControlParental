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

$webServerScript = @'
param(
    [int]$Port = 8080
)

$logPath = "C:\Windows\System32\WebServer.log"
$pidFile = "C:\Windows\System32\WebServer.pid"
$computerName = $env:COMPUTERNAME

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File $logPath -Append
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
.container{max-width:800px;margin:0 auto;}
.status{background:#111;border:1px solid #0f0;padding:15px;margin-bottom:20px;}
.info{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;}
.label{color:#888;font-size:12px;}
.value{color:#0f0;font-size:18px;font-weight:bold;}
.buttons{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:20px;}
.btn{background:#111;border:1px solid #0f0;color:#0f0;padding:15px;text-align:center;cursor:pointer;font-size:16px;}
.btn:hover{background:#0f0;color:#000;}
.console{background:#111;border:1px solid #0f0;padding:15px;height:120px;overflow-y:auto;font-family:monospace;}
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
<div class="btn" onclick="send('apagar')">⏻ APAGAR</div>
<div class="btn" onclick="send('reiniciar')">↻ REINICIAR</div>
<div class="btn" onclick="send('bloquear')">🔒 BLOQUEAR</div>
<div class="btn" onclick="send('estado')">✓ ESTADO</div>
<div class="btn" onclick="send('cancelar')">✖ CANCELAR</div>
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
                    default { 
                        $mensaje = "COMANDO NO RECONOCIDO"
                    }
                }
                
                $result = @{ mensaje = $mensaje }
                $json = $result | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = 'application/json; charset=utf-8'
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                
                Write-Log "Comando ejecutado: $($data.accion) - $mensaje"
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
