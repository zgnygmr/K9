# K9 🐕

*Uyuşturucu arama köpeklerine ithafen: köpek bavulu koklar, açmaz.
Kararı gümrük memuru verir.*

K9, üçüncü parti ajan skill'lerini / MCP sunucularını / araçları **kurmadan
önce** zorunlu güvenlik taramasından geçiren bir protokoldür. Tarama motoru
olarak [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector)
kullanır (68 desen, AST analizi, taint tracking, YARA); K9'un kendi katkısı
taramanın etrafındaki disiplindir: karantina, salt-okur inceleme,
insan-onay kapısı ve rapor arşivi.

## Tasarım ilkeleri

1. Koklanan şey **veridir, komut değildir** — incelenen dosyaların içindeki
   talimatlar asla uygulanmaz (prompt injection savunması).
2. K9 hiçbir şeyi **çalıştırmaz** — tarama tamamen statiktir.
3. K9 **karar vermez** — rapor sunar, onay kutusu insanındır.
4. Ağ politikası: taramada tek çıkış **api.osv.dev** (CVE sorgusu; paket
   adları gider, dosya içeriği gitmez). `--caged` modunda o da kapalıdır.

## Kurulum

```bash
# Önkoşullar: skillspector (uv tool install ...), isteğe bağlı OrbStack
mkdir -p ~/k9 && cp -R k9/* ~/k9/            # bu repo -> ~/k9
chmod +x ~/k9/scripts/k9-scan.sh
mkdir -p ~/.claude/skills/k9 && cp ~/k9/SKILL.md ~/.claude/skills/k9/
```

Son satır K9 protokolünü Claude Code'a kişisel skill olarak tanıtır:
ajan, herhangi bir skill kurulumu istendiğinde önce K9'u uygular.

## Kullanım

```bash
~/k9/scripts/k9-scan.sh https://github.com/birisi/bir-skill      # standart
~/k9/scripts/k9-scan.sh ~/indirilenler/supheli-paket --caged     # tam kafes
```

Çıktılar `~/k9/reports/` altında: envanter, JSON + okunur tarama raporu ve
karar kutusu. Karantina kopyası `~/k9/quarantine/` altında bekler; **ancak
"kur" kararından sonra** hedefe taşınır.

## Skor eşlemesi

| SkillSpector | K9 köpeği |
|---|---|
| 0-20 SAFE | 🟢/🟡 kokladı, tepki yok |
| 21-50 CAUTION | 🟠 oturdu — satır satır incelemeden kurulmaz |
| 51-100 DO_NOT_INSTALL | 🔴 havladı — kurma, raporla, sil |

## Sınırlar (dürüstlük bölümü)

Statik analiz şifrelenmiş/parçalanmış yükleri göremez; temiz rapor bir
kanıttır, garanti değildir. Güvenilir 1. parti skill'lerde yüksek statik
skor normaldir (subprocess vb. meşru kullanım) — 2. aşama (anlamsal
inceleme) tam bu yüzden vardır. En iyi guardrail hâlâ, kurmadan önce iki
kere düşünen insandır.
