# DBX con audit log: build automatica

Questo fork ricostruisce ogni release **stabile** di [t8y2/dbx](https://github.com/t8y2/dbx) con la modifica dell'audit log (branch `feat/web-audit-log`) e pubblica l'immagine su GHCR:

```
ghcr.io/markeclaudio/dbx:<versione>-audit   # es. v0.6.69-audit
ghcr.io/markeclaudio/dbx:latest             # ultima release stabile + audit
```

## Come funziona

Il workflow `.github/workflows/audit-log-release.yml` parte ogni giorno alle 05:41 UTC (o a mano da *Actions → Build DBX release with audit log → Run workflow*):

1. legge l'ultima release stabile di `t8y2/dbx` (le beta sono ignorate);
2. se l'immagine `<versione>-audit` esiste già, si ferma;
3. `prepare-release.sh` scarica esattamente quel tag, verifica che provenga dalla storia di `main` del progetto e riapplica i commit di `feat/web-audit-log`;
4. esegue i test dell'audit log;
5. costruisce l'immagine con il `deploy/Dockerfile` del progetto, con provenance e SBOM, e la pubblica su GHCR.

Se la modifica non si applica più (conflitto) o i test falliscono, la build si ferma, non pubblica nulla e prova ad aprire una issue nel fork. Per riceverla attiva le Issues (*Settings → General → Features → Issues*); in ogni caso GitHub ti avvisa via email del fallimento.

## Regole del fork

- **Questo branch (`main`) contiene solo la build**: i workflow del progetto originale sono stati rimossi perché nel fork partirebbero da soli (es. `daily-beta-release` creerebbe release ogni giorno). **Non usare "Sync fork" su `main`**: non serve, il workflow scarica direttamente le release da `t8y2/dbx`.
- **Il codice della modifica sta in `feat/web-audit-log`**, che è anche il branch della PR verso `t8y2/dbx`. Tienilo lineare: per aggiornarlo usa rebase, non merge.
- **Non creare tag nel fork**: alcuni workflow del progetto originale partono sui tag.

## Risolvere un conflitto

```bash
git fetch https://github.com/t8y2/dbx.git main
git switch feat/web-audit-log
git rebase FETCH_HEAD          # risolvi i conflitti, poi: git add … && git rebase --continue
git push --force-with-lease origin feat/web-audit-log
```

Poi rilancia il workflow a mano. Lo stesso push aggiorna anche la PR.

## Opzioni

| Impostazione | Dove | Default |
| --- | --- | --- |
| Architetture | variabile di repository `AUDIT_PLATFORMS` (*Settings → Secrets and variables → Actions → Variables*) | `linux/amd64`; anche `linux/amd64,linux/arm64` |
| Versione specifica / ricostruzione | *Run workflow* → `release_tag`, `force` | ultima release |

## Sicurezza

- Il workflow usa solo il `GITHUB_TOKEN` con permessi minimi per job (`contents: read`, `packages: write`, `issues: write`): nessun segreto da custodire.
- Le azioni esterne sono fissate per hash di commit; tag, input e variabili sono validati prima dell'uso.
- Il server **non viene aggiornato in automatico**: aggiorna l'immagine quando decidi, idealmente prima in un ambiente di prova.
- GitHub sospende i workflow pianificati dei repository pubblici dopo 60 giorni senza attività: se ricevi l'email di avviso, riattivalo da *Actions*.
- Il pacchetto GHCR può nascere privato: per scaricarlo senza login rendilo pubblico da *Packages → dbx → Package settings*, oppure fai `docker login ghcr.io` sul server con un token in sola lettura (`read:packages`).

Quando la PR verrà accettata da DBX, la build continuerà a funzionare producendo l'immagine originale; a quel punto puoi tornare a `t8y2/dbx:latest` e impostare `DBX_WEB_AUDIT_LOG`.
