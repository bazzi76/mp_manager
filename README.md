# mp_manager

**mp_manager** è uno script Bash che consente di controllare dispositivi relè Modbus TCP (come il [Waveshare Modbus POE ETH Relay](https://www.waveshare.com/wiki/Modbus_POE_ETH_Relay_(C))) usando il tool `modpoll`.

## 📦 Contenuto del progetto

- `mp_manager.sh` – Script principale per leggere o impostare lo stato dei relè
- `mp_manager.conf` – File di configurazione con IP e porta del dispositivo
- `.gitignore` – (facoltativo) File per escludere temporanei o inutili da Git

---

## ⚙️ Requisiti

- **modpoll**: tool da linea di comando per Modbus TCP  
  Scaricabile da: [https://www.modbusdriver.com/modpoll.html](https://www.modbusdriver.com/modpoll.html)

- **bash** (qualsiasi shell compatibile andrà bene)
- **Linux** o WSL/Ubuntu per Windows

---

## 🛠️ Configurazione

Il file `mp_manager.conf` definisce i parametri di rete per il dispositivo Modbus TCP:

```ini
IP=10.2.0.5
PORT=502

