# Kash Stash

**Kash Stash** is a harmless, minimal, cross-platform tray app for sending screenshots and notes to your **Pulse Probes API endpoint(s)**.

…It also happens to support distributed monitoring, automation, configuration management, and business logic — if you’re into that sort of thing.

---

## 🧩 Requirements

* **Python 3.7+** (only if running the `.py` version)
* **`gnome-screenshot`** (Linux only; install with `sudo apt install gnome-screenshot`)
* **`pip`** for Python dependencies (if running from source)
* **`PyInstaller`** (optional; used to build native executables)

---

## ⚙️ Installation

### From Source

```bash
pip install pillow pystray requests
```

### Running the Binary

Run the binary and follow the configuration process.
You’ll be asked to identify your **API endpoints** and **keys** for your node.

You can generate keys under:

> Tools → Probes → API Keys

Create a key for:

* `process_file`

---

## 🖼️ Basic Use Case

For simple screenshot, note, and file indexing:

1. Run the binary and enter:

   * Your **node name**
   * Your **`process_file` key**
2. Leave other fields blank — they aren’t needed for basic use.
3. The app will handle screenshots, notes, and file uploads automatically - just click "take screenshot" or "quick note"

> ⚠️ Windows builds are experimental — test at your own risk.

---

## Before continuing with the medium use case you'll need to configure a pod!
> Go to Tools -> Probes -> Pod Federation to create the pod
> Record the pod key and your node's probes api url (usually probes-node-name.xyzpulseinfra.com if cloud-hosted) when asked during setup
> Make sure that all of the tags you plan on using are EXPLICITLY ADVERTISED TO THE POD - for federation-logic-related reasons the wildcard logic is only available through the UI/"Pull" functionality in the pods api
> Use these tags in your configuration of the pod

## ⚡ Medium Use Case (Semi-Experimental)

Use this setup if you want your agents to **pull scripts and push monitoring data** to Pulse (but not run business logic or queue-based workloads).

1. Create a new **digest in Kash** with the *example agent configuration* (currently Bash-only). Make sure this is in a tag advertised to the pod you created.
2. Create a second **digest** with the contents of `linux_agent.bash`. Again, make sure this is in a tag advertised in the pod.
3. In your template, reference the ID of this second digest as the *logic digest ID*.
4. Restart the agent if it was already running, just in case.

For reference, the config for a medium-level use case should look like this:

```yaml
system_resource_graph:
  type: task
  job:
    timing: 10m
    language: bash
    logic_digest_id: 10641
    done_tags: systemgraph,sysok
    fail_tags: systemgraphfail
    threads: 1
    timeout: 60
```

You should now start seeing monitoring data flow in.
Iterate and expand freely — Pulse is built to observe and evolve.

The end result should resemble the included example screenshot in the repo.

---

## 🧠 Business Logic Use Case (Very Experimental)

If you want to run Pulse for **automation or distributed business logic**, you’ll likely need to advertise a tag for incoming work, locks, and completions to the pod as well, ex:
```yaml
queuetest:
  type: queue
  job:
    language: bash
    logic_digest_id: 12142
    queue_tag:
      queue_tag: automationtest-work
      lookback: 5m
      lock_tag: automationtest-lock
      done_tags: automationtest-done
      fail_tags: automationtest-fail
      retry_failed: y
    threads: 2
    timeout: 300
```

> ⚠️ **Security Notice:**
> Do *not* run sensitive business logic on the same agent used for monitoring or assistance, especially on end-user machines.

### Recommended Secure Setup

**Use a containerized agent** that:

1. Pulls configuration from **encrypted S3** or a **Vault (e.g., OpenBao)** at startup.
2. Runs on a **dedicated Linux host** (e.g., Ubuntu + Docker).
3. Is configured via an entrypoint script that retrieves and decrypts the config at runtime.

Including configs directly inside private container images can work for less sensitive setups, but Vault or encrypted S3 is strongly preferred.

---

### Windows Experimental Setup (If You Must)

If you absolutely need to run automation on Windows endpoints:

1. Create a dedicated local service account:

   ```
   NT SERVICE\KashStash
   ```
2. Store your encrypted config here:

   ```
   C:\ProgramData\KashStash\config.enc
   ```
3. Apply strict ACLs:

   ```bash
   icacls "C:\ProgramData\KashStash" /inheritance:r
   icacls "C:\ProgramData\KashStash" /grant "NT SERVICE\KashStash:(OI)(CI)F" "SYSTEM:(OI)(CI)F"
   ```

   This restricts access to the Kash service user and system account only.
   Any inheritance changes or unauthorized access attempts become **auditable events**.

> 💡 **Safer alternative:** Use a few low-cost machines or Raspberry Pis running Ubuntu + Docker.
> They can pull a pre-configured image from a private repo — much safer than deploying business logic directly to user-facing systems.
> Heck, if you want to, you don't even have to use an image repo, you could hypothetically store a docker build command in Pulse and pull it as a task + run the image as a task as well.

---

## 🧱 Architecture Note

For highly sensitive use-cases:

* Run Kash Stash on **container-only hosts**.
* Avoid direct service-to-service calls inside a single container.
* Instead, split logic between **phased worker agents**:

  * Example:
    **Phase A** → Tag A (input)
    **Phase B** → Tag B (processing)
    **Phase C** → Tag C (output or action)
* This avoids unsafe internal network chatter and keeps logic modular and auditable.
