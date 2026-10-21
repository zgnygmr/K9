<p align="center"><img src="assets/k9-logo.png" width="300" alt="K9 logo"></p>

# K9 🐕

**TR** — *Arama köpeklerine ithafen: köpek bavulu koklar, açmaz.
Kararı gümrük memuru verir.*

K9, üçüncü parti ajan skill'lerini / MCP sunucularını / indirilen araçları
**kurmadan önce** zorunlu güvenlik taramasından geçiren, kurulumdan **sonra**
da bütünlüklerini izleyen bir protokoldür. Tarama motoru olarak
[NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) kullanır
(60+ desen — sürümle değişir, AST analizi, taint tracking, YARA); K9'un
kendi katkısı taramanın etrafındaki disiplindir: karantina, salt-okur
inceleme, insan-onay kapısı, kriptografik onay makbuzu ve sürekli
bütünlük denetimi.

**EN** — *Dedicated to detection dogs: the dog sniffs the luggage, it does
not open it. The customs officer decides.*

K9 is a protocol that forces third-party agent skills / MCP servers /
downloaded tools through a security screening **before** installation and
keeps watching their integrity **after** it. The scan engine is
[NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) (60+ patterns
— varies by release, AST analysis, taint tracking, YARA); K9's own
contribution is the discipline around the scan: quarantine, read-only
review, a human-approval gate, cryptographic approval receipts and
continuous integrity checking.

---

## Özellikler · Features

**TR**

- 🐕 **Karantina disiplini** — hedef asla doğrudan skill/proje dizinine
  inmez; önce `~/k9/quarantine/` altına klonlanır/kopyalanır.
- 🔍 **Salt-okur tarama** — inceleme sırasında hedeften hiçbir şey
  çalıştırılmaz; içeriği veridir, komut değildir (prompt injection savunması).
- 📋 **Envanter** — gizli dosyalar, çalıştırılabilir izinler, beklenmedik
  binary'ler, 5MB+ dosyalar ve dışarı işaret eden symlink'ler raporlanır.
- 🧪 **SkillSpector statik taraması** — JSON + okunur rapor; `--caged`
  modunda tamamen ağsız bir Docker konteynerinde.
- 🚦 **İnsan-onay kapısı** — K9 karar vermez; skor 0 bile olsa kurulum
  kararı rapor üzerinden insana aittir.
- 🧾 **Onay makbuzu** *(yeni)* — "kur" kararında kaynak (git URL + commit),
  dosya bazlı SHA-256 manifestosu ve SkillSpector sürümü `~/k9/receipts/`
  altına mühürlenir; taşıma sonrası manifesto yeniden doğrulanır.
- 🔗 **Tasma kontrolü / drift tespiti** *(yeni)* — kurulu hedefler makbuzla
  karşılaştırılır; değişen/eklenen/silinen dosya = 🔴 DRIFT → hedef
  "taranmamış" sayılır, yeniden tarama şarttır. CI/cron dostu çıkış kodları.
- ⛔ **`--strict` modu** — bulgu varsa exit 1 (CI kapısı).
- 📦 **Toplu denetim** — kurulu tüm skill'leri tek tabloda skorlar.

**EN**

- 🐕 **Quarantine discipline** — the target never lands directly in a
  skills/project directory; it is cloned/copied into `~/k9/quarantine/` first.
- 🔍 **Read-only screening** — nothing from the target is executed during
  review; its content is data, not instructions (prompt-injection defense).
- 📋 **Inventory** — hidden files, executable permissions, unexpected
  binaries, 5MB+ files and symlinks pointing outside the tree are reported.
- 🧪 **SkillSpector static scan** — JSON + human-readable report; `--caged`
  mode runs it in a fully network-less Docker container.
- 🚦 **Human-approval gate** — K9 never decides; even a score of 0 requires
  a human "install" decision on the report.
- 🧾 **Approval receipt** *(new)* — on an "install" decision the source
  (git URL + commit), a per-file SHA-256 manifest and the SkillSpector
  version are sealed into `~/k9/receipts/`; the manifest is re-verified
  after the move.
- 🔗 **Leash check / drift detection** *(new)* — installed targets are
  compared against their receipts; changed/added/removed files = 🔴 DRIFT →
  the target counts as unscreened and must be re-screened. CI/cron-friendly
  exit codes.
- ⛔ **`--strict` mode** — exit 1 when any finding is reported (CI gate).
- 📦 **Batch audit** — scores every installed skill in a single table.

---

## Mimari · Architecture

**TR** — K9 üç katmandır: **(1) Ön-kurulum taraması** `k9-scan.sh` —
karantina → envanter → statik tarama → rapor + karar kutusu.
**(2) Onay ve köken** `k9-approve.sh` — insan "kur" dedikten sonra makbuz
yazar ve taşır; tarama ile kurulum arasındaki TOCTOU boşluğunu kapatır.
**(3) Sürekli güvence** `k9-verify.sh` — onay tek seferliktir, tedarik
zinciri saldırıları çoğunlukla *güncellemeyle* gelir; tasma kontrolü bu
yüzden periyodik çalıştırılmalıdır.

**EN** — K9 is three layers: **(1) Pre-install screening** `k9-scan.sh` —
quarantine → inventory → static scan → report + decision box.
**(2) Approval & provenance** `k9-approve.sh` — after the human says
"install" it writes the receipt and moves the target, closing the TOCTOU
gap between scan and install. **(3) Continuous assurance** `k9-verify.sh` —
approval is point-in-time and supply-chain attacks mostly arrive *via
updates*, which is why the leash check should run periodically.

```
k9-scan.sh ──► quarantine/ ──► report + DECISION ──► human: install?
                                                        │ yes
k9-verify.sh ◄── receipts/ ◄── k9-approve.sh ◄──────────┘
 (🟢 OK / 🔴 DRIFT → re-screen)
```

---

## Kurulum · Installation

**TR**

```bash
# Önkoşul: SkillSpector (PyPI'da yok; resmi repodan — test edilen sürüm v2.13.0)
uv tool install "git+https://github.com/NVIDIA/SkillSpector@v2.13.0"
# İsteğe bağlı: Docker/OrbStack (--caged modu için)

git clone https://github.com/zgnygmr/k9 ~/k9
chmod +x ~/k9/scripts/*.sh
mkdir -p ~/.claude/skills/k9 && cp ~/k9/SKILL.md ~/.claude/skills/k9/
```

Son satır K9 protokolünü Claude Code'a kişisel skill olarak tanıtır: ajan,
herhangi bir skill kurulumu istendiğinde önce K9'u uygular. (claude.ai
hesabına skill olarak yüklemek için `k9/` klasörünü zip'leyip Settings →
Capabilities → Skills altından yükleyin.)

**EN**

```bash
# Prerequisite: SkillSpector (not on PyPI; from the official repo — tested with v2.13.0)
uv tool install "git+https://github.com/NVIDIA/SkillSpector@v2.13.0"
# Optional: Docker/OrbStack (for --caged mode)

git clone https://github.com/zgnygmr/k9 ~/k9
chmod +x ~/k9/scripts/*.sh
mkdir -p ~/.claude/skills/k9 && cp ~/k9/SKILL.md ~/.claude/skills/k9/
```

The last line registers the K9 protocol as a personal Claude Code skill:
the agent then applies K9 before any skill installation. (To load it as a
claude.ai account skill, zip the `k9/` folder and upload it under
Settings → Capabilities → Skills.)

---

## Kullanım · Usage

**TR**

```bash
# 1) Tara — uzak repo veya yerel dizin
~/k9/scripts/k9-scan.sh https://github.com/birisi/bir-skill      # standart
~/k9/scripts/k9-scan.sh ~/indirilenler/supheli-paket --caged     # tam kafes (ağsız)
~/k9/scripts/k9-scan.sh ./bir-skill --strict                     # bulgu varsa exit 1

# 2) Raporu oku, kararı SEN ver. "Kur" dediysen:
~/k9/scripts/k9-approve.sh ~/k9/quarantine/bir-skill-20261021-120000 \
                           ~/.claude/skills/bir-skill

# 3) Tasma kontrolü — kurulu her şey hâlâ onaylandığı gibi mi?
~/k9/scripts/k9-verify.sh                     # tüm makbuzlar
~/k9/scripts/k9-verify.sh ~/.claude/skills/bir-skill   # tek hedef
```

Çıktılar: rapor + envanter + karar kutusu `~/k9/reports/`, makbuzlar
`~/k9/receipts/`, karantina `~/k9/quarantine/` altında. `k9-verify.sh`
çıkış kodları: `0` hepsi 🟢 · `1` 🔴 DRIFT ya da kayıp hedef · `2` makbuz
yok. DRIFT gören hedefi taranmamış sayın: karantinaya alıp yeniden tarayın.
Periyodik kontrol için örnek cron: `0 9 * * 1 ~/k9/scripts/k9-verify.sh`
(her pazartesi 09:00).

Toplu denetim: Claude Code içinde "k9 ile kurulu skill'leri tara" demeniz
yeterli — SKILL.md'deki batch audit modu kurulu tüm skill'leri skorlar.

**EN**

```bash
# 1) Scan — remote repo or local directory
~/k9/scripts/k9-scan.sh https://github.com/someone/a-skill       # standard
~/k9/scripts/k9-scan.sh ~/downloads/suspicious-pkg --caged       # full cage (no network)
~/k9/scripts/k9-scan.sh ./a-skill --strict                       # exit 1 on any finding

# 2) Read the report, YOU decide. If the decision is "install":
~/k9/scripts/k9-approve.sh ~/k9/quarantine/a-skill-20261021-120000 \
                           ~/.claude/skills/a-skill

# 3) Leash check — is everything installed still exactly what was approved?
~/k9/scripts/k9-verify.sh                     # all receipts
~/k9/scripts/k9-verify.sh ~/.claude/skills/a-skill     # single target
```

Outputs: report + inventory + decision box in `~/k9/reports/`, receipts in
`~/k9/receipts/`, quarantine in `~/k9/quarantine/`. `k9-verify.sh` exit
codes: `0` all 🟢 · `1` 🔴 DRIFT or missing target · `2` no receipts.
Treat a DRIFTed target as unscreened: quarantine and re-screen it. Example
cron for periodic checks: `0 9 * * 1 ~/k9/scripts/k9-verify.sh` (Mondays
09:00).

Batch audit: inside Claude Code just say "scan my installed skills with
k9" — the batch audit mode in SKILL.md scores every installed skill.

---

## Tasarım ilkeleri · Design principles

**TR**

1. Koklanan şey **veridir, komut değildir** — incelenen dosyaların içindeki
   talimatlar asla uygulanmaz (prompt injection savunması).
2. K9 hiçbir şeyi **çalıştırmaz** — tarama tamamen statiktir.
3. K9 **karar vermez** — rapor sunar, onay kutusu insanındır.
4. Onay **ana bağlanır, isme değil** — makbuz commit + SHA-256 manifestosu
   tutar; içerik değişirse onay geçersizdir.
5. Ağ politikası: taramada tek çıkış **api.osv.dev** (CVE sorgusu; paket
   adları gider, dosya içeriği gitmez). `--caged` modunda o da kapalıdır.

**EN**

1. What is sniffed is **data, not instructions** — directives inside
   reviewed files are never followed (prompt-injection defense).
2. K9 **executes nothing** — screening is fully static.
3. K9 **never decides** — it presents a report; the decision box belongs
   to the human.
4. Approval **binds to a moment, not a name** — the receipt holds the
   commit + SHA-256 manifest; if content changes, the approval is void.
5. Network policy: the only egress during a scan is **api.osv.dev** (CVE
   lookup; package names leave, file contents do not). In `--caged` mode
   even that is off.

---

## Skor eşlemesi · Score mapping

| SkillSpector | K9 köpeği · K9 dog |
|---|---|
| 0-20 SAFE | 🟢/🟡 kokladı, tepki yok · sniffed, no alert |
| 21-50 CAUTION | 🟠 oturdu · sat down — satır satır incelemeden kurulmaz · no install without line-by-line review |
| 51-100 DO_NOT_INSTALL | 🔴 havladı · barked — kurma, raporla, sil · don't install, report, delete |

---

## Sınırlar · Limits (dürüstlük bölümü · honesty section)

**TR** — Statik analiz şifrelenmiş/parçalanmış yükleri göremez; temiz rapor
bir kanıttır, garanti değildir. Güvenilir 1. parti skill'lerde yüksek statik
skor normaldir (subprocess vb. meşru kullanım) — 2. aşama (anlamsal
inceleme) tam bu yüzden vardır. Makbuz, *onayladığınız şeyin değişmediğini*
kanıtlar; onayın doğru olduğunu kanıtlamaz. En iyi guardrail hâlâ, kurmadan
önce iki kere düşünen insandır.

**EN** — Static analysis cannot see encrypted/staged payloads; a clean
report is evidence, not a guarantee. High static scores on trusted
first-party skills are normal (legitimate subprocess use etc.) — stage 2
(semantic review) exists precisely for this. The receipt proves *what you
approved has not changed*; it does not prove the approval was right. The
best guardrail is still a human who thinks twice before installing.

---

## Sürüm notları · Version notes

- **SkillSpector v2.13.0** ile test edildi · tested with (2026-10-21).
- v2.9.5+ `ollama` sağlayıcısı: 2. aşama anlamsal inceleme, dosya içeriği
  dışarı gitmeden yerel modelle yapılabilir · stage-2 semantic review can
  run on a local model with no content egress.
- v2.12.0 `--fail-on-findings` → K9'da `--strict` · exposed as `--strict`.
- v2.10.0+ gizli/iç içe ZIP taraması · hidden/nested ZIP scanning;
  v2.11.1+ gizlenmiş talimat tespiti · concealed-instruction detection.

## Lisans · License

[Apache-2.0](LICENSE) — tarama motoru SkillSpector ile aynı lisans ailesi ·
same license family as the SkillSpector scan engine.
