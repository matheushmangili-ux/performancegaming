# Win11 Gaming Suite

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Windows](https://img.shields.io/badge/Windows-11%2024H2%2B-0078D6?logo=windows)](https://www.microsoft.com/windows/windows-11)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/matheushmangili-ux/performancegaming)](https://github.com/matheushmangili-ux/performancegaming/releases)

Ferramenta de auditoria **read-only** que escaneia o Windows 11, identifica oportunidades de otimização para gaming competitivo, explica **por quê** cada ajuste importa e gera um `.bat` personalizado apenas com os fixes aplicáveis ao seu PC.

Não é um script de "aplica tudo cego". É **análise → explicação → fix personalizado → benchmark → detecção de regressão**.

---

## Instalação (one-liner)

PowerShell **como Administrador**:

```powershell
irm https://raw.githubusercontent.com/matheushmangili-ux/performancegaming/main/Install-Win11GamingSuite.ps1 | iex
```

Ou manual:

```powershell
git clone https://github.com/matheushmangili-ux/performancegaming.git
cd performancegaming
.\Install-Win11GamingSuite.ps1
```

---

## O que tem dentro

| Script | Função |
|---|---|
| **Win11-Gaming-Audit.ps1** | Scan + relatório (console/HTML/JSON) + `fix.bat` personalizado + `revert.bat` |
| **Win11-Gaming-Benchmark.ps1** | Wrapper PresentMon: AVG FPS, 1% low, 0.1% low, p99 frametime, compare A/B |
| **Win11-Gaming-Sentinel.ps1** | Detecta drift pós-Windows-Update via tarefa agendada + toast nativo |
| **Install-Win11GamingSuite.ps1** | Instalador + menu interativo |

---

## Features

### Auditoria (15 categorias)

- ⚡ **Energia** — plano Ultimate Performance, core parking, hibernação
- 🎮 **GPU** — HAGS, MPO bug stutter, idade do driver, advisories vendor-specific
- 🎯 **Gaming Features** — Game Bar, Game DVR, Fullscreen Optimizations
- 🛠️ **Serviços** — DiagTrack, SysMain, WSearch, Xbox, etc. com razão de cada um
- 🌐 **Rede** — Nagle, NetworkThrottlingIndex, RSS, SystemResponsiveness
- 🔒 **Segurança** — VBS/HVCI com tradeoff explicado
- 📊 **Scheduler** — Win32PrioritySeparation, MMCSS Tasks\Games
- 💾 **Memória** — Memory Compression, uso atual
- 💿 **Storage** — TRIM, LastAccess, espaço livre, tipo de disco
- 📡 **Telemetria** — AllowTelemetry, Cortana, Advertising ID
- 🚀 **Startup** — OneDrive, quantidade de itens
- ⏱️ **Timer** — useplatformtick (Win11 24H2 fix)
- 🧠 **RAM XMP/EXPO** — detecta se está rodando abaixo da spec
- 🌡️ **Temperaturas** — via WMI (opcional)
- 🎲 **Jogos** — detecta Steam/Epic/Riot, destaca competitivos

### Cada achado traz

- **Severidade** (Crítico / Alto / Médio / Info / OK)
- **Estado atual** no seu PC
- **Por quê** impacta FPS/latência
- **Impacto esperado** em números
- **Comando de fix** pronto
- **Comando de revert** (gerado em paralelo)

### Score 0-100

Cálculo ponderado por severidade para acompanhar o progresso ao longo do tempo.

---

## Uso

### Scan básico (não modifica nada)

```powershell
.\Win11-Gaming-Audit.ps1
```

### Scan + gerar fix personalizado

```powershell
.\Win11-Gaming-Audit.ps1 -GenerateFix -Profile Balanced
# gera: Win11-Gaming-Fix-Balanced.bat + Win11-Gaming-Revert.bat
```

Profiles:
- `Safe` — só Críticos
- `Balanced` — Críticos + Altos (default)
- `Competitive` — Críticos + Altos + Médios

### Benchmark A/B com PresentMon

```powershell
# Baixe PresentMon em https://github.com/GameTechDev/PresentMon/releases
# Coloque em .\tools\PresentMon.exe

.\Win11-Gaming-Benchmark.ps1 -Process cs2 -Label before -Duration 60
# aplica fix, reinicia
.\Win11-Gaming-Benchmark.ps1 -Process cs2 -Label after -Duration 60
.\Win11-Gaming-Benchmark.ps1 -Compare "benchmark-before-*.json,benchmark-after-*.json"
```

### Sentinel (detecta drift pós-update)

```powershell
# Depois de aplicar o fix e confirmar que está ótimo:
.\Win11-Gaming-Sentinel.ps1 -Install

# Sentinel roda a cada logon. Se o Windows Update reverteu algo,
# você recebe toast nativo Windows.

.\Win11-Gaming-Sentinel.ps1 -Status
.\Win11-Gaming-Sentinel.ps1 -Reapply
```

### Modo Watch (re-audita periodicamente)

```powershell
.\Win11-Gaming-Audit.ps1 -Watch 30 -OutputJson history.json
```

---

## Por que existe

As ferramentas populares (WinUtil, Atlas OS, BoosterX, Optimizer, Wintoys) aplicam ajustes em **blanket**, sem explicar **por quê** ou medir impacto. Após um Windows Update cumulativo, várias otimizações voltam silenciosamente ao padrão — e você nunca sabe.

Esta suite resolve isso em 3 camadas:

1. **Personalizado** — só fixa o que seu PC precisa, baseado em scan real
2. **Educativo** — cada achado tem razão e impacto estimado, você aprende
3. **Resiliente** — Sentinel detecta quando o Windows silenciosamente reverteu e te avisa

---

## Requisitos

- Windows 11 24H2 ou superior
- PowerShell 5.1+ (nativo)
- Administrador (para aplicar fixes e criar scheduled task)

---

## Aviso

Estes scripts modificam registro, serviços e configurações de sistema. Todos os fixes são reversíveis via `Win11-Gaming-Revert.bat` e um ponto de restauração é criado automaticamente. Ainda assim:

- **Leia os achados antes de aplicar**
- Desabilitar VBS/HVCI reduz segurança (tradeoff FPS vs hardening)
- Desabilitar Print Spooler quebra impressora
- Desabilitar serviços Xbox quebra Game Pass
- Use por sua conta e risco

---

## Contribuindo

PRs bem-vindos, especialmente:

- Novos testes em `Win11-Gaming-Audit.ps1` (novas categorias)
- Driver bug knowledge base (YAML)
- Traduções do relatório
- Perfis específicos por jogo (NVCP/Adrenalin tweaks)

---

## Licença

MIT — ver [LICENSE](LICENSE).

---

## Créditos

Inspirado em [PresentMon (Intel)](https://github.com/GameTechDev/PresentMon), [Chris Titus WinUtil](https://christitus.com/windows-tool/), e nas discussões eternas em r/pcgaming sobre o que realmente melhora FPS no Windows.
