# ================= CONFIG =================
$BotToken = "TOKEN TELEGRAM"
$Api = "https://api.telegram.org/bot$BotToken"

# whitelist chat id (user / group)
$AllowedChats = @(CHAT ID, CHAT ID)

$Offset = 0

# DEFAULT NAMESPACE UNTUK HPA SCALE
$DefaultHpaNamespace = "app"
# =========================================

function Send-Telegram {
    param (
        [long]$chatId,
        [string]$text
    )

    Invoke-RestMethod `
        -Uri "$Api/sendMessage" `
        -Method Post `
        -ContentType "application/json" `
        -Body (@{
            chat_id = $chatId
            text    = $text
        } | ConvertTo-Json)
}

Write-Host "🚀 AKS Telegram Bot running..."

while ($true) {
    try {
        $updates = Invoke-RestMethod "$Api/getUpdates?offset=$Offset"

        foreach ($u in $updates.result) {
            $Offset = $u.update_id + 1
            if (-not $u.message) { continue }

            $chatId = $u.message.chat.id
            $text   = $u.message.text.Trim()

            # ===== WHITELIST CHECK =====
            if ($AllowedChats -notcontains $chatId) { continue }

            # ===== COMMAND HANDLER =====

            if ($text -eq "/start") {
                Send-Telegram $chatId @"
🤖 AKS Telegram Bot siap!

Commands:
/getns
/getnodes
/getpods <namespace>
/gethpa <namespace>
/scalehpa <hpa-name> <max>

Contoh:
/gethpa app
/scalehpa backend-hpa 5
"@
            }

            elseif ($text -eq "/getns") {
                $out = kubectl get ns 2>&1 | Out-String
                Send-Telegram $chatId $out
            }

            elseif ($text -eq "/getnodes") {
                $out = kubectl get nodes 2>&1 | Out-String
                Send-Telegram $chatId $out
            }

            elseif ($text -like "/getpods*") {
                $parts = $text.Split(" ", 2)
                if ($parts.Count -lt 2) {
                    Send-Telegram $chatId "❌ Format:`n/getpods <namespace>"
                    continue
                }

                $namespace = $parts[1]
                $out = kubectl get pods -n $namespace 2>&1 | Out-String
                Send-Telegram $chatId $out
            }

            # ===== GET HPA BY NAMESPACE =====
            elseif ($text -like "/gethpa*") {
                $parts = $text.Split(" ", 2)

                if ($parts.Count -lt 2) {
                    Send-Telegram $chatId "❌ Format:`n/gethpa <namespace>`nContoh: /gethpa app"
                    continue
                }

                $namespace = $parts[1]
                $out = kubectl get hpa -n $namespace 2>&1 | Out-String

                Send-Telegram $chatId @"
📊 HPA di namespace *$namespace*:

$out
"@
            }

            # ===== SCALE HPA (BY NAME, FIXED NAMESPACE) =====
            elseif ($text -like "/scalehpa*") {
                $parts = $text.Split(" ")

                if ($parts.Count -ne 3) {
                    Send-Telegram $chatId "❌ Format:`n/scalehpa <hpa-name> <maxReplicas>`nContoh: /scalehpa backend-hpa 5"
                    continue
                }

                $hpaName = $parts[1]
                $max     = [int]$parts[2]

                # PATCH HPA DI NAMESPACE YANG BENAR
                kubectl patch hpa $hpaName -n $DefaultHpaNamespace `
                  --type merge `
                  -p "{""spec"":{""maxReplicas"":$max}}" 2>&1 | Out-Null

                $out = kubectl get hpa $hpaName -n $DefaultHpaNamespace | Out-String

                Send-Telegram $chatId @"
✅ HPA *$hpaName* maxReplicas berhasil diubah ke *$max*

$out
"@
            }

            else {
                Send-Telegram $chatId @"
❌ Command tidak dikenal

Available commands:
/getns
/getnodes
/getpods <namespace>
/gethpa <namespace>
/scalehpa <hpa-name> <max>
"@
            }
        }
    }
    catch {
        Write-Host "❌ Error: $_"
    }

    Start-Sleep -Seconds 2
}
