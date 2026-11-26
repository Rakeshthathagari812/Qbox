# QBOX AI server

Runs the AI4Bharat models on our own machine:

| Job | Model | Languages |
|---|---|---|
| Speech-to-text | IndicConformer 600M (multilingual) | Telugu, Hindi, Kannada, Tamil (English uses Google on the phone) |
| Translation | IndicTrans2 distilled (en-indic 200M, indic-en 200M, indic-indic 320M) | English, Telugu, Hindi, Kannada, Tamil, any direction |
| Speaking aloud | Google Android TTS, on the phone | (not here) |

Free (MIT licence). Nothing said or translated leaves our servers or is stored.
Only the QBOX backend talks to this server; phones never reach it directly.

## First-time setup

From this folder (`QBOX\qbox_ai`):

```powershell
python -m venv .venv
$env:OPENSSL_CONF = "$PWD\network_fix.cnf"
.venv\Scripts\python -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
.venv\Scripts\python -m pip install -r requirements.txt -c constraints.txt
```

`network_fix.cnf`: the office network drops Python 3.14's newer secure-connection
handshake (pip hangs with "handshake timed out" / "SSL EOF" while curl works). This file
makes Python use the classic handshake. `download_models.py` applies it by itself.

Then download the models (about 5-6 GB, once). They are free but need a HuggingFace
account (email only, no documents):

1. Make an account at https://huggingface.co and verify your email.
2. Logged in, open each page and click **Agree and access repository**:
   - https://huggingface.co/ai4bharat/indictrans2-en-indic-dist-200M
   - https://huggingface.co/ai4bharat/indictrans2-indic-en-dist-200M
   - https://huggingface.co/ai4bharat/indictrans2-indic-indic-dist-320M
   - https://huggingface.co/ai4bharat/indic-conformer-600m-multilingual
3. Profile picture -> **Settings -> Access Tokens -> Create new token**, type **Read**, copy it.
4. Create `qbox_ai\.env` (never commit it, never paste the token in chat):
   ```
   HF_TOKEN=<your token>
   ```
5. Download (run again to continue if the internet drops):
   ```powershell
   .venv\Scripts\python download_models.py
   ```

## Run it

```powershell
.venv\Scripts\python -m uvicorn ai_server.main:app --port 8090
```

- Loading the models takes about a minute; the backend's `/api/language/status`
  turns `{"online": true}` when they are ready.
- Uses about 5-6 GB of memory. No graphics card needed.
- Start it with the backend whenever you test voice/translation. Without it the app
  quietly uses the phone's own speech and translation.

## Settings (`qbox_ai\.env`)

| Setting | Default | Meaning |
|---|---|---|
| `QBOX_AI_KEY` | dev key | Shared secret; must equal `QBOX_AI_KEY` in `qbox_backend/.env`. Change before going live |
| `QBOX_AI_APP_ENV` | `dev` | `production` = refuses to start with the dev key |
| `QBOX_AI_PRELOAD` | `true` | Load all models at start (else each on first use) |
| `QBOX_AI_ASR_DECODING` | `rnnt` | `rnnt` = more accurate, `ctc` = faster |
| `QBOX_AI_NUM_BEAMS` | `4` | Translation search width: higher = slightly better, slower |
| `QBOX_AI_THREADS` | `0` | CPU threads (0 = automatic) |

## Safety

- The models come with Python code. Only the code whose fingerprint is in
  `ai_server/model_code.json` is run; pickled weights are refused.
- `transformers` 4 has known holes that are fixed only in version 5, which the models do not run on
  (tried 2026-11-25). None of the affected parts (Trainer, downloading code, LightGlue, X-CLIP,
  save_pretrained) is used here. Keep this server closed to the internet: only the QBOX backend
  may reach it.

## Check it

```powershell
.venv\Scripts\python -m pytest
```

The tests use pretend models, so they run without the download.

## Folders

```
ai_server/
  main.py        the API: /health, /translate, /speech-to-text (all need the shared key)
  models.py      loads IndicTrans2 and IndicConformer (pinned versions) and runs them
  indic_text.py  prepares text for IndicTrans2 and cleans its answer (script swap, Moses,
                 shop glossary, full stop, never lose a number)
  audio.py       reads the phone's WAV recording and cleans it (silence cut, quiet voice louder)
  languages.py   app language codes -> model codes
  config.py      settings
download_models.py  one-time model download
network_fix.cnf     classic secure-connection handshake for this network (see setup)
models/             the downloaded models (not in Git)
tests/
```

## Going live

- Run it on the same server as the backend (it listens only on 127.0.0.1), or on a
  separate machine reached over a private network. Never expose port 8090 to the internet.
- A server with 8+ GB RAM works on CPU; a graphics card (GPU) makes it several times faster.
- Set the same private `QBOX_AI_KEY` (32+ characters) here and in the backend.
