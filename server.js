/**
 * mp-manager-web — server.js
 * Backend Node.js/Express per pilotare mp_manager.sh via HTTP REST API
 *
 * Avvio: node server.js
 * Assicurati che mp_manager.sh e mp_manager.conf siano nella stessa cartella
 * oppure imposta MP_MANAGER_PATH e MP_MANAGER_CONF come variabili d'ambiente.
 */

const express = require("express");
const { exec } = require("child_process");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

// Percorso allo script (modificabile via env)
const MP_SCRIPT = process.env.MP_MANAGER_PATH
  ? path.resolve(process.env.MP_MANAGER_PATH)
  : path.resolve(__dirname, "mp_manager.sh");

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// ---------- utility ----------

/**
 * Esegue lo script con i parametri dati e restituisce stdout/stderr.
 * @param {string[]} args - Array di argomenti da passare allo script
 * @returns {Promise<{stdout: string, stderr: string, code: number}>}
 */
function runScript(args = []) {
  const safeArgs = args.map((a) => {
    // Permette solo caratteri alfanumerici, trattini, punti e numeri
    if (!/^[\w\-\.]+$/.test(a)) throw new Error(`Argomento non valido: ${a}`);
    return a;
  });

  const cmd = `bash "${MP_SCRIPT}" ${safeArgs.join(" ")}`;
  console.log(`[exec] ${cmd}`);

  return new Promise((resolve) => {
    exec(cmd, { timeout: 10000 }, (err, stdout, stderr) => {
      resolve({
        stdout: stdout || "",
        stderr: stderr || "",
        code: err ? err.code ?? 1 : 0,
      });
    });
  });
}

/**
 * Fa il parsing dell'output di modpoll per estrarre gli stati coil.
 * Riga tipica: "[0]: 1" oppure "[1]: 0"
 */
function parseCoilStates(stdout) {
  const states = [];
  const lines = stdout.split("\n");
  for (const line of lines) {
    const match = line.match(/\[(\d+)\]:\s*([01])/);
    if (match) {
      states.push({ coil: parseInt(match[1]), state: parseInt(match[2]) });
    }
  }
  return states;
}

// ---------- API ----------

// GET /api/status/relays — stato di tutti i relè
app.get("/api/status/relays", async (req, res) => {
  try {
    const result = await runScript(["status", "-r"]);
    const relays = parseCoilStates(result.stdout);
    res.json({ ok: true, relays, raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// GET /api/status/inputs — stato degli ingressi digitali
app.get("/api/status/inputs", async (req, res) => {
  try {
    const result = await runScript(["status", "-d"]);
    const inputs = parseCoilStates(result.stdout);
    res.json({ ok: true, inputs, raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relay/:num/on — accendi relè N
app.post("/api/relay/:num/on", async (req, res) => {
  const num = parseInt(req.params.num);
  if (isNaN(num) || num < 0) return res.status(400).json({ ok: false, error: "Numero relè non valido" });
  try {
    const result = await runScript(["on", String(num)]);
    res.json({ ok: true, relay: num, action: "on", raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relay/:num/off — spegni relè N
app.post("/api/relay/:num/off", async (req, res) => {
  const num = parseInt(req.params.num);
  if (isNaN(num) || num < 0) return res.status(400).json({ ok: false, error: "Numero relè non valido" });
  try {
    const result = await runScript(["off", String(num)]);
    res.json({ ok: true, relay: num, action: "off", raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relay/:num/pulse?duration=0.5 — pulse relè N
app.post("/api/relay/:num/pulse", async (req, res) => {
  const num = parseInt(req.params.num);
  const duration = parseFloat(req.query.duration || "0.5");
  if (isNaN(num) || num < 0) return res.status(400).json({ ok: false, error: "Numero relè non valido" });
  if (isNaN(duration) || duration <= 0 || duration > 60) return res.status(400).json({ ok: false, error: "Durata non valida (0–60s)" });
  try {
    const result = await runScript(["pulse", String(num), String(duration)]);
    res.json({ ok: true, relay: num, action: "pulse", duration, raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relays/all-on — accendi tutti
app.post("/api/relays/all-on", async (req, res) => {
  try {
    const result = await runScript(["all-on"]);
    res.json({ ok: true, action: "all-on", raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relays/all-off — spegni tutti
app.post("/api/relays/all-off", async (req, res) => {
  try {
    const result = await runScript(["all-off"]);
    res.json({ ok: true, action: "all-off", raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relays/toggle-all — inverti tutti
app.post("/api/relays/toggle-all", async (req, res) => {
  try {
    const result = await runScript(["toggle-all"]);
    res.json({ ok: true, action: "toggle-all", raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ---------- avvio ----------
app.listen(PORT, () => {
  console.log(`mp-manager-web in ascolto su http://localhost:${PORT}`);
  console.log(`Script: ${MP_SCRIPT}`);
});
