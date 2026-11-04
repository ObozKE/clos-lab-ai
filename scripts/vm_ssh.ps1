param(
    [string]$User = "engineer",
    [string]$Command = "uptime"
)

$key = "C:\Users\Admin\.ssh\id_ed25519"
$ip = "192.168.122.130"

ssh -i $key -o StrictHostKeyChecking=no -o BatchMode=yes "${User}@${ip}" $Command
