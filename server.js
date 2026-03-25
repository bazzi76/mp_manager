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

// GET /api/relay/:num/mode — leggi modalità relè N
// Risposta: { ok, relay, mode: 0-3, modeName: "Normal"|"Linkage"|"Toggle"|"Trigger" }
app.get("/api/relay/:num/mode", async (req, res) => {
  const num = parseInt(req.params.num);
  if (isNaN(num) || num < 0) return res.status(400).json({ ok: false, error: "Numero relè non valido" });
  try {
    const result = await runScript(["get-mode", String(num)]);
    // Output modpoll per holding register: "[4096]: 1" oppure "[4096]:  1"
    const match = result.stdout.match(/\[\d+\]:\s*(\d+)/);
    if (!match) return res.status(502).json({ ok: false, error: "Nessuna risposta dal dispositivo", raw: result.stdout });
    const mode = parseInt(match[1]);
    const modeNames = ["Normal", "Linkage", "Toggle", "Trigger"];
    res.json({ ok: true, relay: num, mode, modeName: modeNames[mode] ?? "Unknown", raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// POST /api/relay/:num/mode/:value — imposta modalità relè N
// :value = 0 (Normal) | 1 (Linkage) | 2 (Toggle) | 3 (Trigger)
app.post("/api/relay/:num/mode/:value", async (req, res) => {
  const num   = parseInt(req.params.num);
  const value = parseInt(req.params.value);
  if (isNaN(num)   || num   < 0)        return res.status(400).json({ ok: false, error: "Numero relè non valido" });
  if (isNaN(value) || value < 0 || value > 3) return res.status(400).json({ ok: false, error: "Modalità non valida (0-3)" });
  try {
    const result = await runScript(["set-mode", String(num), String(value)]);
    const modeNames = ["Normal", "Linkage", "Toggle", "Trigger"];
    res.json({ ok: true, relay: num, mode: value, modeName: modeNames[value], raw: result.stdout });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// GET /api/relays/modes — leggi modalità di tutti i relè in una sola chiamata
app.get("/api/relays/modes", async (req, res) => {
  const modeNames = ["Normal", "Linkage", "Toggle", "Trigger"];
  try {
    // Leggiamo i MAX_RELAYS+1 registri in parallelo
    // Non sappiamo MAX_RELAYS qui, usiamo la conf — leggiamo fino a 16 e filtriamo
    // In alternativa leggiamo uno per uno con Promise.all dal frontend
    // Per semplicità eseguiamo get-mode per ogni relay 0-15 in parallelo
    const promises = Array.from({ length: 16 }, (_, i) =>
      runScript(["get-mode", String(i)]).then(result => {
        const match = result.stdout.match(/\[\d+\]:\s*(\d+)/);
        const mode = match ? parseInt(match[1]) : null;
        return { relay: i, mode, modeName: mode !== null ? (modeNames[mode] ?? "Unknown") : null, error: match ? null : "no response" };
      })
    );
    const modes = await Promise.all(promises);
    res.json({ ok: true, modes });
  } catch (e) {
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ---------- avvio ----------
app.listen(PORT, () => {
  console.log(`mp-manager-web in ascolto su http://localhost:${PORT}`);
  console.log(`Script: ${MP_SCRIPT}`);
});

