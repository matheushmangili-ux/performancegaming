<#
.SYNOPSIS
    Setup-DiscordServer - Cria estrutura completa de servidor Discord via REST API.

.DESCRIPTION
    Cria roles, categorias, canais, permissoes e mensagens de welcome/regras
    pra comunidade PerformanceGaming BR do zero. Idempotente: se o canal ja
    existir, pula.

.PARAMETER Token
    Token do bot Discord. Obtenha em: https://discord.com/developers/applications

.PARAMETER GuildId
    ID do servidor. Habilite Developer Mode (Config > Avancado) e clique com
    botao direito no server > Copiar ID do Servidor.

.PARAMETER CleanFirst
    CUIDADO: apaga todos os canais e roles existentes antes de criar os novos.

.EXAMPLE
    # 1) Crie app em https://discord.com/developers/applications
    # 2) Bot > Reset Token > copie
    # 3) OAuth2 > URL Generator > scopes: bot + applications.commands
    #    Permissions: Administrator. Copie URL, abra, adicione ao seu server.
    # 4) No Discord, botao direito no server > Copiar ID do Servidor.
    # 5) Rode:
    .\Setup-DiscordServer.ps1 -Token "MTIzNDU2..." -GuildId "987654321"
#>

param(
    [Parameter(Mandatory=$true)] [string]$Token,
    [Parameter(Mandatory=$true)] [string]$GuildId,
    [switch]$CleanFirst,
    [string]$GithubUrl = 'https://github.com/matheushmangili-ux/performancegaming',
    [string]$ProductUrl = 'https://github.com/matheushmangili-ux/performancegaming'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$API = 'https://discord.com/api/v10'
$headers = @{
    'Authorization' = "Bot $Token"
    'Content-Type'  = 'application/json'
    'User-Agent'    = 'PerformanceGamingBR/1.0'
}

# ============================================================================
# HELPERS (com rate limit)
# ============================================================================
function Invoke-Discord {
    param($Method, $Path, $Body)
    $uri = "$API$Path"
    $params = @{ Method=$Method; Uri=$uri; Headers=$headers }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress) }
    try {
        $r = Invoke-RestMethod @params
        Start-Sleep -Milliseconds 350   # rate limit safe margin
        return $r
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 429) {
            Write-Host "  [rate limited, aguardando 3s]" -ForegroundColor Yellow
            Start-Sleep 3
            return Invoke-Discord @PSBoundParameters
        }
        Write-Host "  [erro $code em $Method $Path]: $_" -ForegroundColor Red
        return $null
    }
}

function Write-Step { param($msg) Write-Host "  > $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Skip { param($msg) Write-Host "    [skip] $msg" -ForegroundColor DarkGray }

# ============================================================================
# BANNER
# ============================================================================
Clear-Host
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor Magenta
Write-Host '   DISCORD SERVER SETUP - PerformanceGaming BR' -ForegroundColor Magenta
Write-Host ('=' * 70) -ForegroundColor Magenta
Write-Host ''

# Valida token
Write-Step 'Validando token do bot...'
$me = Invoke-Discord -Method GET -Path '/users/@me'
if (-not $me) { throw 'Token invalido ou sem permissao.' }
Write-Ok "Bot: $($me.username) (id $($me.id))"

$guild = Invoke-Discord -Method GET -Path "/guilds/$GuildId"
if (-not $guild) { throw "Guild $GuildId nao encontrado ou bot nao esta nele." }
Write-Ok "Server: $($guild.name)"
Write-Host ''

# ============================================================================
# CLEAN (opcional)
# ============================================================================
if ($CleanFirst) {
    Write-Host '  ATENCAO: -CleanFirst vai APAGAR todos canais e roles nao-default.' -ForegroundColor Red
    Write-Host '  Digite "CONFIRMO" para prosseguir:' -NoNewline
    if ((Read-Host) -ne 'CONFIRMO') { Write-Host '  Cancelado.' -ForegroundColor Yellow; exit }

    Write-Step 'Removendo canais existentes...'
    $channels = Invoke-Discord -Method GET -Path "/guilds/$GuildId/channels"
    foreach ($c in $channels) {
        Invoke-Discord -Method DELETE -Path "/channels/$($c.id)" | Out-Null
        Write-Skip "removido: $($c.name)"
    }

    Write-Step 'Removendo roles custom...'
    $roles = Invoke-Discord -Method GET -Path "/guilds/$GuildId/roles"
    foreach ($r in $roles) {
        if ($r.name -eq '@everyone' -or $r.managed) { continue }
        Invoke-Discord -Method DELETE -Path "/guilds/$GuildId/roles/$($r.id)" | Out-Null
        Write-Skip "role removida: $($r.name)"
    }
}

# ============================================================================
# ROLES
# ============================================================================
Write-Host ''
Write-Step 'Criando roles...'

$rolesToCreate = @(
    @{name='Owner';        color=0xFFD700; hoist=$true;  mentionable=$false}
    @{name='Admin';        color=0xFF6B6B; hoist=$true;  mentionable=$true}
    @{name='Mod';          color=0x9B59B6; hoist=$true;  mentionable=$true}
    @{name='Parceiro';     color=0xF39C12; hoist=$true;  mentionable=$true}
    @{name='Pro User';     color=0x5865F2; hoist=$true;  mentionable=$false}
    @{name='Beta Tester';  color=0x2ECC71; hoist=$true;  mentionable=$true}
    @{name='Top Score';    color=0x1ABC9C; hoist=$false; mentionable=$false}
    @{name='Competitivo';  color=0xE74C3C; hoist=$false; mentionable=$true}
)

$createdRoles = @{}
$existingRoles = Invoke-Discord -Method GET -Path "/guilds/$GuildId/roles"
foreach ($r in $rolesToCreate) {
    $exist = $existingRoles | Where-Object name -eq $r.name | Select-Object -First 1
    if ($exist) { $createdRoles[$r.name] = $exist.id; Write-Skip "role ja existe: $($r.name)"; continue }
    $body = @{
        name = $r.name
        color = $r.color
        hoist = $r.hoist
        mentionable = $r.mentionable
        permissions = '0'
    }
    $newRole = Invoke-Discord -Method POST -Path "/guilds/$GuildId/roles" -Body $body
    if ($newRole) { $createdRoles[$r.name] = $newRole.id; Write-Ok "role: $($r.name)" }
}

# ============================================================================
# CATEGORIAS + CANAIS
# ============================================================================
Write-Host ''
Write-Step 'Criando categorias e canais...'

# Estrutura: @{Nome da Categoria = @(canais)}
# Tipo canal: 0=texto, 2=voz, 4=categoria
$structure = @(
    @{
        category = 'BOAS-VINDAS'
        channels = @(
            @{name='regras';       type=0; topic='Leia antes de tudo'}
            @{name='anuncios';     type=0; topic='Anuncios oficiais'}
            @{name='bem-vindo';    type=0; topic='Apresente-se aqui'}
            @{name='roles';        type=0; topic='Escolha seus roles via reacao'}
        )
    },
    @{
        category = 'GUIA'
        channels = @(
            @{name='como-comecar'; type=0; topic='Fluxo de uso da ferramenta'}
            @{name='faq';          type=0; topic='Perguntas frequentes'}
            @{name='roadmap';      type=0; topic='Features em desenvolvimento'}
            @{name='sugestoes';    type=0; topic='Sugestoes da comunidade'}
        )
    },
    @{
        category = 'FERRAMENTA'
        channels = @(
            @{name='discussao-geral'; type=0; topic='Papo geral sobre otimizacao'}
            @{name='suporte-tecnico'; type=0; topic='Duvidas e erros. Poste com template.'}
            @{name='bug-report';      type=0; topic='Reporte bugs com print + SO + versao'}
            @{name='posta-seu-score'; type=0; topic='Compartilhe resultado do audit'}
            @{name='antes-depois';    type=0; topic='Showcase de comparativos'}
        )
    },
    @{
        category = 'GAMING'
        channels = @(
            @{name='cs2';            type=0; topic='Counter-Strike 2'}
            @{name='valorant';       type=0; topic='Valorant'}
            @{name='outros-jogos';   type=0; topic='Apex, LoL, etc.'}
            @{name='hardware-build'; type=0; topic='Builds, reviews, compras'}
        )
    },
    @{
        category = 'VIP (Pro)'
        channels = @(
            @{name='pro-lounge';    type=0; topic='Canal exclusivo Pro'}
            @{name='early-access';  type=0; topic='Features beta exclusivas'}
            @{name='voice-pro';     type=2}
        )
    },
    @{
        category = 'OFF-TOPIC'
        channels = @(
            @{name='papo-livre';  type=0; topic='Assuntos gerais'}
            @{name='musica';      type=0; topic='Compartilhe musicas'}
            @{name='voice-geral'; type=2}
        )
    },
    @{
        category = 'STAFF'
        channels = @(
            @{name='mod-chat'; type=0; topic='Privado staff'}
            @{name='logs';     type=0; topic='Logs do bot'}
        )
        staffOnly = $true
    }
)

$createdChannels = @{}
$existingChannels = Invoke-Discord -Method GET -Path "/guilds/$GuildId/channels"

foreach ($cat in $structure) {
    $catName = $cat.category
    $existCat = $existingChannels | Where-Object { $_.name -eq $catName -and $_.type -eq 4 } | Select-Object -First 1
    if ($existCat) {
        $catId = $existCat.id
        Write-Skip "categoria existe: $catName"
    } else {
        $catBody = @{ name = $catName; type = 4 }
        # Staff only: permissoes restritas
        if ($cat.staffOnly) {
            $catBody.permission_overwrites = @(
                @{ id = $GuildId; type = 0; deny = '1024' }   # @everyone sem view_channel
                @{ id = $createdRoles['Admin']; type = 0; allow = '1024' }
                @{ id = $createdRoles['Mod']; type = 0; allow = '1024' }
            )
        }
        # VIP Pro: so Pro User + staff
        if ($catName -eq 'VIP (Pro)') {
            $catBody.permission_overwrites = @(
                @{ id = $GuildId; type = 0; deny = '1024' }
                @{ id = $createdRoles['Pro User']; type = 0; allow = '1024' }
                @{ id = $createdRoles['Admin']; type = 0; allow = '1024' }
                @{ id = $createdRoles['Mod']; type = 0; allow = '1024' }
            )
        }
        $newCat = Invoke-Discord -Method POST -Path "/guilds/$GuildId/channels" -Body $catBody
        if ($newCat) { $catId = $newCat.id; Write-Ok "categoria: $catName" }
    }

    foreach ($ch in $cat.channels) {
        $existCh = $existingChannels | Where-Object { $_.name -eq $ch.name -and $_.type -eq $ch.type } | Select-Object -First 1
        if ($existCh) { $createdChannels[$ch.name] = $existCh.id; Write-Skip "canal existe: $($ch.name)"; continue }
        $chBody = @{
            name = $ch.name
            type = $ch.type
            parent_id = $catId
        }
        if ($ch.topic) { $chBody.topic = $ch.topic }
        $newCh = Invoke-Discord -Method POST -Path "/guilds/$GuildId/channels" -Body $chBody
        if ($newCh) { $createdChannels[$ch.name] = $newCh.id; Write-Ok "canal: $($ch.name)" }
    }
}

# ============================================================================
# MENSAGENS INICIAIS
# ============================================================================
Write-Host ''
Write-Step 'Postando mensagens iniciais...'

function Send-Msg {
    param($ChannelName, $Content, $Embed)
    $id = $createdChannels[$ChannelName]
    if (-not $id) { Write-Skip "canal $ChannelName nao achado"; return $null }
    $body = @{}
    if ($Content) { $body.content = $Content }
    if ($Embed)   { $body.embeds = @($Embed) }
    $r = Invoke-Discord -Method POST -Path "/channels/$id/messages" -Body $body
    if ($r) { Write-Ok "msg em #$ChannelName" }
    return $r
}

# REGRAS
$regras = @"
**REGRAS - PerformanceGaming BR**

1. **Respeito acima de tudo.** Sem toxicidade, racismo, homofobia, misoginia.
2. **Proibido spam.** Self-promo so em canal autorizado com aval da staff.
3. **Use o canal certo.** Duvida tecnica -> #suporte-tecnico, nao #off-topic.
4. **Antes de perguntar,** leia #faq e #como-comecar.
5. **Bug report** -> #bug-report com: versao, SO, mensagem de erro, passos.
6. **Compartilhe** seu score em #posta-seu-score (aceita print do HTML).
7. **Review-bomb** ou hate de outras ferramentas nao sera tolerado. Comparacao tecnica OK.
8. **Proibido pedir crack/keygen** de software pago. Ban direto.
9. **Venda de servicos fora do server** = timeout 24h.
10. **Decisao da staff e final.** Apelacao via DM ao @Owner.

Ao continuar no server, voce concorda com estas regras.
"@
Send-Msg -ChannelName 'regras' -Content $regras | Out-Null

# BEM-VINDO
$bemvindo = @"
**BEM-VINDO(A) AO PERFORMANCEGAMING BR**

Comunidade brasileira de otimizacao real para gaming em Windows 11.

**Comece aqui:**
- Leia <#$($createdChannels['regras'])>
- Baixe a ferramenta: $GithubUrl
- Rode o audit e poste seu score em <#$($createdChannels['posta-seu-score'])>
- Duvidas? <#$($createdChannels['suporte-tecnico'])>

Se joga CS/Val/Apex competitivo, pega o role 'Competitivo' em <#$($createdChannels['roles'])>.
Se comprou o Pro, tem acesso exclusivo em VIP Lounge.

Boa otimizacao.
"@
Send-Msg -ChannelName 'bem-vindo' -Content $bemvindo | Out-Null

# COMO COMECAR
$comoComecar = @"
**COMO USAR A FERRAMENTA**

**1. Baixe**
$GithubUrl

**2. Instalacao one-liner (PowerShell como admin):**
``````
irm https://raw.githubusercontent.com/matheushmangili-ux/performancegaming/main/Install-Win11GamingSuite.ps1 | iex
``````

**3. Modo rapido (tudo automatico):**
``````
.\Win11-Gaming-Audit.ps1 -Auto
``````

**4. Modo manual (passo a passo):**
1. ``.\Win11-Gaming-Audit.ps1`` (scan read-only, veja o score)
2. ``.\Win11-Gaming-Audit.ps1 -GenerateFix`` (gera .bat personalizado)
3. Leia o .bat no notepad e rode como admin
4. Reinicie
5. ``.\Win11-Gaming-Audit.ps1`` de novo (valida)
6. ``.\Win11-Gaming-Sentinel.ps1 -Install`` (blinda contra Windows Update)

**Reverter se der errado:**
``.\Win11-Gaming-Revert.bat`` ou restore point (rstrui.exe)

**Profiles:**
- Safe = so criticos (minimo risco)
- Balanced = criticos + altos (DEFAULT)
- Competitive = tudo (pro gaming, desabilita VBS)
"@
Send-Msg -ChannelName 'como-comecar' -Content $comoComecar | Out-Null

# FAQ
$faq = @"
**PERGUNTAS FREQUENTES**

**Q: Meu antivirus acusa como virus, e?**
A: Falso positivo. Scripts PowerShell nao-assinados sao heuristicamente flagados. Codigo aberto, pode auditar no GitHub.

**Q: Funciona em laptop?**
A: Sim, mas modo Ultimate Performance reduz bateria. Prefira profile Balanced.

**Q: Preciso reinstalar Windows?**
A: Nao. Tudo reversivel via Revert.bat ou restore point.

**Q: Posso rodar em PC corporativo?**
A: Nao. Politicas de dominio podem ser alteradas - pede ao seu TI.

**Q: Por que meu jogo ficou lento apos o fix?**
A: Shader cache pode ter sido apagado. Primeira sessao recompila. Normal, volta em 30min.

**Q: O que muda entre Free e Pro?**
A: Free = scan + fix manual. Pro = -Auto + Sentinel + suporte prioritario + updates Pro features.

**Q: Windows Update desfaz as otimizacoes?**
A: Sim, as vezes. Por isso existe o Sentinel - detecta e te avisa via toast nativo Win11.

**Q: Quanto de FPS eu ganho?**
A: Varia muito. Tipicamente +5-15% 1% lows. Gains maiores em CPUs gargaladas.

**Q: Posso contribuir?**
A: Sim. PR no GitHub sao bem-vindos. Driver KB community-driven em breve.
"@
Send-Msg -ChannelName 'faq' -Content $faq | Out-Null

# POSTA SEU SCORE (template)
$scoreTemplate = @"
**COMO POSTAR SEU SCORE**

Use este template:

``````
Setup: Ryzen X / RTX Y / RAM Z GB
Score: XX/100
Criticos: [MPO, Nagle, ...]
Jogo principal: CS2 / Valorant / etc.
``````

Anexe print do console ou do HTML gerado.

**Recompensa:** score >= 85 apos o fix ganha role **Top Score** (turquesa).
"@
Send-Msg -ChannelName 'posta-seu-score' -Content $scoreTemplate | Out-Null

# SUPORTE TEMPLATE
$suporteTemplate = @"
**ANTES DE PEDIR AJUDA**

Poste neste formato:

``````
SO: Windows 11 24H2 (build XXXXX)
CPU / GPU / RAM:
Jogo afetado:
Problema:
O que ja tentou:
Print/erro:
``````

Sem essas infos, ninguem consegue ajudar direito. Staff vai ignorar posts sem contexto.
"@
Send-Msg -ChannelName 'suporte-tecnico' -Content $suporteTemplate | Out-Null

# BUG REPORT TEMPLATE
$bugTemplate = @"
**TEMPLATE BUG REPORT**

``````
Versao da suite: v1.0.0
SO: Win 11 24H2 build XXXXX
Hardware: [CPU / GPU / RAM]
Comando rodado: .\Win11-Gaming-Audit.ps1 -...
Erro:
Log completo: (anexe arquivo)
Reproducivel: sim / nao / as vezes
Passos pra reproduzir:
  1.
  2.
  3.
``````
"@
Send-Msg -ChannelName 'bug-report' -Content $bugTemplate | Out-Null

# ANUNCIO DE ABERTURA
$anuncio = @"
@everyone

**SERVER ABERTO**

Cansei de ver thread de "stutter no CS2" que ninguem resolve de verdade.
Cansei de "FPS booster" que so apaga temp files e finge que otimizou.

Entao criei o **PerformanceGaming Suite**:

- **Auditor read-only** que escaneia 15 categorias tecnicas do Win11
- **Gera .bat personalizado** so com o que SEU PC precisa
- **Benchmark A/B real** via PresentMon (1% low, 0.1% low, p99 frametime)
- **Sentinel** que detecta quando Windows Update reverte tuas otimizacoes
- **Tabela comparativa** antes vs depois com delta em %

Tudo **open source**: $GithubUrl
Pro (R$ 39 lifetime) desbloqueia auto-apply + suporte prioritario + updates.

Este server e pra:
- Suporte tecnico real
- Trocar scores e comparativos
- Debate honesto sobre o que funciona e o que e placebo
- Beta testers influenciam o roadmap

**@everyone** posta seu score em <#$($createdChannels['posta-seu-score'])>

GG e boa otimizacao.
"@
Send-Msg -ChannelName 'anuncios' -Content $anuncio | Out-Null

# ============================================================================
# FINAL
# ============================================================================
Write-Host ''
Write-Host ('=' * 70) -ForegroundColor Green
Write-Host '   SERVER CRIADO COM SUCESSO' -ForegroundColor Green
Write-Host ('=' * 70) -ForegroundColor Green
Write-Host ''
Write-Host '   PROXIMOS PASSOS MANUAIS:' -ForegroundColor Yellow
Write-Host '   1. Config do server > Imagem/Banner: upload manual (API nao permite)' -ForegroundColor Gray
Write-Host '   2. Instale bots gratuitos:' -ForegroundColor Gray
Write-Host '      - MEE6 (welcome auto): https://mee6.xyz' -ForegroundColor DarkGray
Write-Host '      - Carl-bot (reaction roles): https://carl.gg' -ForegroundColor DarkGray
Write-Host '      - Ticket Tool (suporte): https://tickettool.xyz' -ForegroundColor DarkGray
Write-Host '   3. Em #roles, configure reaction roles via Carl-bot' -ForegroundColor Gray
Write-Host '   4. Atribua role Admin/Mod aos parceiros' -ForegroundColor Gray
Write-Host '   5. Gere link de convite permanente no canal #bem-vindo' -ForegroundColor Gray
Write-Host ''
Write-Host '   Acesse o server em: Discord > ' + $guild.name -ForegroundColor Cyan
Write-Host ''
