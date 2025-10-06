import requests
import yaml
import os
import threading
import time
import random
from datetime import datetime
import json
import base64
from bash_executor import BashExecutor

LOCK_PATH = os.path.expanduser("~/.kash_stash_locks")

def ensure_lock_dir():
    if not os.path.exists(LOCK_PATH):
        os.makedirs(LOCK_PATH, exist_ok=True)

def queue_lockfile_name(queue_jobname, digest_id):
    return os.path.join(LOCK_PATH, f"{queue_jobname}-{digest_id}.lock")

def queue_lockfile_exists(job_name, digest_id):
    return os.path.isfile(queue_lockfile_name(job_name, digest_id))

def create_queue_lockfile(job_name, digest_id, info=None):
    ensure_lock_dir()
    with open(queue_lockfile_name(job_name, digest_id), 'w') as f:
        f.write(json.dumps({
            "created": datetime.utcnow().isoformat(),
            "info": info or {}
        }))

def remove_queue_lockfile(job_name, digest_id):
    try:
        os.remove(queue_lockfile_name(job_name, digest_id))
    except Exception:
        pass

def parse_tags(s):
    # comma separated string to list
    if not s:
        return []
    if isinstance(s, list):  # support either way
        return s
    return [i.strip() for i in s.split(',') if i.strip()]

def parse_iso8601_as_epoch(s):
    return datetime.fromisoformat(s).timestamp() if s else 0

class QueueBoss:
    def __init__(self, endpoint_getter):
        self.bash_executor = BashExecutor()
        self.get_current_endpoint = endpoint_getter
    def _now_iso(self):
        return datetime.utcnow().isoformat()

    def fetch_logic_script(self, digest_id):
        """
        Fetch the logic/script content from a digest, unwrapping ['output']['data']['content'] or similar.
        Returns the script content as a UTF-8 string, or None if not found.
        """
        import requests, json
        endpoint = self.get_current_endpoint()
        node_name = endpoint.get('DIGEST_NODE_NAME', endpoint.get('NODE_NAME',''))
        probe_id = endpoint.get('DIGEST_PROBE_ID')
        probe_key = endpoint.get('DIGEST_PROBE_KEY')
        if not (digest_id and probe_id and probe_key):
            print("[queue_boss] No LOGIC_DIGEST or probe/key configured.")
            return None

        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        payload = {
            "method": "GET",
            "endpoint": f"/digests/{digest_id}",
            "digest_id": digest_id
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        try:
            print(f"[queue_boss] Pulling logic digest: {digest_id}")
            resp = requests.post(url, json=payload, headers=headers, timeout=30)
            resp.raise_for_status()
            digest_obj = resp.json()
            print("[queue_boss] Logic digest API response:")
            print(json.dumps(digest_obj, indent=2))
            # Robust extraction – check various nestings
            content = None
            if "output" in digest_obj and isinstance(digest_obj["output"], dict):
                output = digest_obj["output"]
                if "content" in output:
                    content = output["content"]
                elif "data" in output and isinstance(output["data"], dict) and "content" in output["data"]:
                    content = output["data"]["content"]
            elif "content" in digest_obj:
                content = digest_obj["content"]
            if not content:
                print("[queue_boss] Could not find script content in logic digest!")
                return None
            print("[queue_boss] Extracted script (first 200 chars):")
            print(content[:200])
            return content
        except Exception as e:
            print(f"[queue_boss] Failed to fetch logic digest: {e}")
            return None

    def fetch_queue_digests(self, queue_tag, lookback_s):
        """Use the LIST digests probe (listdigests_probe_id/key) to get digests for this queue_tag in the lookback window."""
        endpoint = self.get_current_endpoint()
        probe_id = endpoint.get('LISTDIGESTS_PROBE_ID')
        probe_key = endpoint.get('LISTDIGESTS_PROBE_KEY')
        node_name = endpoint.get('LISTDIGESTS_NODE_NAME', endpoint.get('NODE_NAME',''))
        if not (probe_id and probe_key):
            raise RuntimeError("List digests endpoint not configured!")

        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        start_dt = (datetime.utcnow() - datetime.timedelta(seconds=lookback_s)).strftime('%Y-%m-%dT%H:%M:%S')
        params = {"tags": queue_tag, "start_date": start_dt, "per_page": 1000}
        payload = {
            "method": "GET",
            "endpoint": "/digests",
            "params": params
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        resp = requests.post(url, json=payload, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        entries = []
        for k in ('feedentries','digests','output'):
            if k in data and isinstance(data[k], list):
                entries.extend(data[k])
        if not entries and isinstance(data.get('output',None), list):
            entries = data['output']
        return entries

    def fetch_lock_digests(self, lock_tag, lookback_s, device_tag):
        """Grab all lock digests from the backend in the lookback window for this lock_tag and this device."""
        endpoint = self.get_current_endpoint()
        probe_id = endpoint.get('LISTDIGESTS_PROBE_ID')
        probe_key = endpoint.get('LISTDIGESTS_PROBE_KEY')
        node_name = endpoint.get('LISTDIGESTS_NODE_NAME', endpoint.get('NODE_NAME',''))
        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        start_dt = (datetime.utcnow() - datetime.timedelta(seconds=lookback_s)).strftime('%Y-%m-%dT%H:%M:%S')
        params = {"tags": lock_tag, "start_date": start_dt, "per_page": 1000}
        payload = {
            "method": "GET",
            "endpoint": "/digests",
            "params": params
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        resp = requests.post(url, json=payload, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        entries = []
        for k in ('feedentries','digests','output'):
            if k in data and isinstance(data[k], list):
                entries.extend(data[k])
        if not entries and isinstance(data.get('output',None), list):
            entries = data['output']
        # Only return locks with a tag for device_tag (if specified)
        if device_tag:
            return [d for d in entries if device_tag in parse_tags(d.get("tags"))]
        return entries

    def fetch_fail_digests(self, fail_tag, lookback_s, device_tag):
        """Same as fetch_lock_digests, but for failure digests (so we can skip ones that failed and shouldn't retry)."""
        endpoint = self.get_current_endpoint()
        probe_id = endpoint.get('LISTDIGESTS_PROBE_ID')
        probe_key = endpoint.get('LISTDIGESTS_PROBE_KEY')
        node_name = endpoint.get('LISTDIGESTS_NODE_NAME', endpoint.get('NODE_NAME',''))
        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        start_dt = (datetime.utcnow() - datetime.timedelta(seconds=lookback_s)).strftime('%Y-%m-%dT%H:%M:%S')
        params = {"tags": fail_tag, "start_date": start_dt, "per_page": 1000}
        payload = {
            "method": "GET",
            "endpoint": "/digests",
            "params": params
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        resp = requests.post(url, json=payload, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        entries = []
        for k in ('feedentries','digests','output'):
            if k in data and isinstance(data[k], list):
                entries.extend(data[k])
        if not entries and isinstance(data.get('output',None), list):
            entries = data['output']
        if device_tag:
            return [d for d in entries if device_tag in parse_tags(d.get("tags"))]
        return entries

    def post_digest(self, content, tags, filename=None, context_prompt=None):
        """
        Post a text digest as a file (base64), matching user/desktop uploader format.
        - content: bytes or string (text report content)
        - tags: string, tags to attach
        - filename: optional; default system_resource_graph_YYYYMMDD_HHMMSS.txt
        - context_prompt: optional (can pass for trace/debug)
        """
        endpoint = self.get_current_endpoint()
        probe_id = endpoint.get('PROBE_ID')
        node_name = endpoint.get('NODE_NAME')
        probe_key = endpoint.get('PROBE_KEY')
        if filename is None:
            filename = f"system_resource_graph_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.txt"
        # Encode as needed
        if isinstance(content, str):
            file_bytes = content.encode('utf-8')
        else:
            file_bytes = content
        file_content_b64 = base64.b64encode(file_bytes).decode('utf-8')

        payload = {
            "file": {
                "content": file_content_b64,
                "filename": filename,
                "content_type": "text/plain"
            },
            "tags": tags,
            "device": endpoint.get("DEVICE", ""),
            "context_prompt": context_prompt or ""
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        try:
            resp = requests.post(url, json=payload, headers=headers, timeout=15)
            resp.raise_for_status()
            print(f"[queue_boss] Posted digest file '{filename}' with tags: {tags}")
            return resp.json()
        except Exception as e:
            print(f"[queue_boss] Failed posting digest: {e}")
            return None

    def process_queue_job(self, job_name, job_conf):
        """
        Implements full queue logic:
          - finds digests with queue_tag in the lookback window,
          - skips locked/fail-tagged ones (unless retry_failed is set),
          - posts lock, runs script, posts done/fail result, handles lockfile
        """
        queue_obj = job_conf["queue_tag"] if isinstance(job_conf["queue_tag"], dict) else job_conf.get("queue_tag", {})
        queue_tag = job_conf["queue_tag"] if isinstance(job_conf["queue_tag"], str) else queue_obj.get("queue_tag", "")
        lookback = queue_obj.get("lookback", job_conf.get("lookback", "2m"))
        lock_digests = queue_obj.get("lock_digests", job_conf.get("lock_digests", "y")).lower() != "n"
        lock_tag = queue_obj.get("lock_tag", job_conf.get("lock_tag", f"{job_name}-lock"))
        done_tags = parse_tags(queue_obj.get("done_tags", job_conf.get("done_tags", f"{job_name}-done")))
        fail_tags = parse_tags(queue_obj.get("fail_tags", job_conf.get("fail_tags", f"{job_name}-fail")))
        retry_failed = queue_obj.get("retry_failed", job_conf.get("retry_failed", "y")).lower() == "y"
        device_tag = self.get_current_endpoint().get("DEVICE")
        threads = int(job_conf.get('threads', 1))
        timeout = int(job_conf.get("timeout", 900))
        random_stagger = lambda i: random.uniform(2, 5) * i

        # Lookback string to seconds
        def lookback_to_seconds(lb):
            units = {'s':1, 'm':60, 'h':3600, 'd':86400, 'w':604800}
            if lb.isdigit():
                return int(lb)
            for unit,mult in units.items():
                if lb.endswith(unit):
                    return int(float(lb[:-1]) * mult)
            raise ValueError(f"Cannot parse lookback '{lb}'")
        lookback_s = lookback_to_seconds(lookback)

        def worker_loop(thread_id):
            while True:
                try:
                    digests = self.fetch_queue_digests(queue_tag, lookback_s)
                    if not digests:
                        time.sleep(3)
                        continue

                    # === Backend lock and done digests for device
                    lock_digests_list = self.fetch_lock_digests(lock_tag, lookback_s, device_tag=device_tag)
                    done_digests_list = self.fetch_done_digests(done_tags[0] if done_tags else '', lookback_s, device_tag=device_tag)

                    # Map digest id -> lock digest
                    locked_map = {}
                    for d in lock_digests_list:
                        content_id = d.get('content')
                        if content_id:
                            locked_map[content_id] = d

                    # Map digest id -> done digest
                    done_ids = set(d.get('content') for d in done_digests_list if 'content' in d)

                    # Candidate work
                    work = []
                    for d in digests:
                        digest_id = str(d['id'])
                        # If already done by this agent in this window, skip forever!
                        if digest_id in done_ids:
                            continue

                        # Locally locked?
                        if queue_lockfile_exists(job_name, digest_id):
                            # Check lockfile age, if >timeout, allow retry, else skip
                            lock_file_path = queue_lockfile_name(job_name, digest_id)
                            try:
                                with open(lock_file_path, "r") as lf:
                                    info = json.load(lf)
                                created = info.get("created")
                                if created:
                                    age = (datetime.utcnow() - datetime.fromisoformat(created)).total_seconds()
                                    if age < timeout:
                                        continue  # Lockfile fresh, skip
                                    else:
                                        # Stale lock, allow retry (remove lockfile)
                                        print(f"[queue_boss] Lockfile for {digest_id} is stale, re-trying.")
                                        remove_queue_lockfile(job_name, digest_id)
                            except Exception:
                                pass  # If error with lockfile, allow retry

                        # Backend lock for this id?
                        backendlock = locked_map.get(digest_id)
                        if backendlock:
                            # Also check lock age.
                            age = self._lock_digest_age_sec(backendlock)
                            if age < timeout:
                                continue
                            else:
                                print(f"[queue_boss] Backend lock for {digest_id} is stale (>timeout), will retry.")

                        # If we reach here, the job is NOT done and NOT locked (or stale lock) -- so process!
                        work.append(d)

                    if not work:
                        print(f"[queue_boss] ({job_name}) No unlocked/undone queue digests in lookback ({lookback}) for thread {thread_id}")
                        time.sleep(5)
                        continue

                    for d in work:
                        digest_id = d['id']
                        if queue_lockfile_exists(job_name, digest_id):
                            continue
                        # POST lock digest (content: digest id)
                        lock_tags = [lock_tag, job_name, queue_tag]
                        if device_tag: lock_tags.append(device_tag)
                        self.post_digest(content=str(digest_id), tags=lock_tags)
                        create_queue_lockfile(job_name, digest_id)
                        # --------- actual bash business logic run ---------
                        logic_digest_id = job_conf["logic_digest_id"]
                        script = self.fetch_logic_script(logic_digest_id)
                        if not script:
                            print(f"[queue_boss] Could not fetch script for bash queue job {job_name}")
                            continue
                        digest_content_input = d.get("content", "")
                        input_file = None
                        if digest_content_input:
                            import tempfile
                            input_file = tempfile.NamedTemporaryFile(delete=False)
                            input_file.write(digest_content_input.encode('utf-8'))
                            input_file.close()
                        print(f"[queue_boss] ({job_name}) Thread {thread_id} running on digest {digest_id}")
                        result = self.bash_executor.run_script(
                            job_name, script, job_conf,
                            input_path=input_file.name if input_file else None,
                            job_digest=d
                        )
                        if input_file:
                            os.unlink(input_file.name)
                        # ----------- handle result and post as done or fail -----------
                        try:
                            output_obj = json.loads(result["stdout"])
                        except Exception:
                            output_obj = {}
                        successful = (result["retcode"] == 0) and output_obj.get("content")
                        if successful:
                            res_tags = done_tags.copy()
                        else:
                            res_tags = fail_tags.copy()
                        if "tags" in output_obj:
                            res_tags += parse_tags(output_obj["tags"])
                        content_b64 = output_obj.get("content", "")
                        try:
                            post_content = base64.b64decode(content_b64).decode("utf-8")
                        except Exception:
                            post_content = "[Invalid base64 result]" if content_b64 else (result["stdout"] or "")
                        self.post_digest(content=post_content, tags=res_tags+[job_name])
                        remove_queue_lockfile(job_name, digest_id)
                        time.sleep(random_stagger(thread_id))
                except Exception as e:
                    print(f"[queue_boss] Exception in queue job worker {job_name}: {e}")
                    time.sleep(5)

        for i in range(threads):
            t = threading.Thread(target=worker_loop, args=(i,), daemon=True)
            t.start()

    def start(self):
        ensure_lock_dir()
        config_digest = self._fetch_config_yaml()
        if not config_digest:
            print("[queue_boss] Could not fetch config digest. Exiting.")
            return
        config = config_digest

        for name, job in config.items():
            if not isinstance(job, dict) or 'type' not in job or 'job' not in job:
                print(f"[queue_boss] Skipping invalid job entry '{name}' (missing type/job)")
                continue
            job_type = job['type']
            job_conf = job['job']
            language = job_conf.get('language')
            if language != 'bash':
                continue

            if job_type in ('setup', 'onetime'):
                t = threading.Thread(target=self.run_setup_or_onetime, args=(name, job_conf, job_type), daemon=True)
                t.start()
            elif job_type == 'task':
                self.schedule_task_job(name, job_conf)
            elif job_type == 'queue':
                endpoint = self.get_current_endpoint()
                if not (endpoint.get("LISTDIGESTS_PROBE_ID") and endpoint.get("LISTDIGESTS_PROBE_KEY")):
                    print(f"[queue_boss] ERROR: Queue job {name} requires configured list-digests endpoint! Skipping.")
                    continue
                print(f"[queue_boss] Starting queue job thread(s) for {name}")
                self.process_queue_job(name, job_conf)
            else:
                print(f"[queue_boss] Unknown job type {job_type} for job {name}")

    def run_setup_or_onetime(self, job_name, job_conf, job_type):
        """Run a setup or onetime bash job if no lockfile exists/left behind; creates lockfile after run."""
        if queue_lockfile_exists(job_name, "setup"):
            print(f"[queue_boss] Lockfile for setup/onetime job '{job_name}' exists, skipping.")
            return
        digest_id = job_conf.get("logic_digest_id")
        if not digest_id:
            print(f"[queue_boss] No logic_digest_id for job {job_name}")
            return
        script_content = self.fetch_logic_script(digest_id)
        if not script_content:
            print(f"[queue_boss] No script found for job {job_name}")
            return

        device_tag = self.get_current_endpoint().get("DEVICE")
        lock_tag = job_conf.get("lock_tag", f"{job_name}-lock")
        done_tags = parse_tags(job_conf.get("done_tags", f"{job_name}-done"))
        fail_tags = parse_tags(job_conf.get("fail_tags", f"{job_name}-fail"))

        # Post lock (setup jobs lock on name + "setup")
        lock_tags = [lock_tag, job_name, "setup"]
        if device_tag:
            lock_tags.append(device_tag)
        self.post_digest(content="setup", tags=lock_tags)
        create_queue_lockfile(job_name, "setup")

        # Run the script
        print(f"[queue_boss] Running {job_type} bash job {job_name}")
        result = self.bash_executor.run_script(job_name, script_content, job_conf)

        # Handle result, post done/fail as needed
        try:
            output_obj = json.loads(result["stdout"])
        except Exception:
            output_obj = {}
        successful = (result["retcode"] == 0) and output_obj.get("content")
        if successful:
            res_tags = done_tags.copy()
        else:
            res_tags = fail_tags.copy()
        if "tags" in output_obj:
            res_tags += parse_tags(output_obj["tags"])
        content_b64 = output_obj.get("content", "")
        try:
            post_content = base64.b64decode(content_b64).decode("utf-8")
        except Exception:
            post_content = "[Invalid base64 result]" if content_b64 else (result["stdout"] or "")
        self.post_digest(content=post_content, tags=res_tags+[job_name])
        print(f"[queue_boss] [{job_name}] Setup/Onetime {('success' if successful else 'fail')}, lockfile created and result posted.")

    def schedule_task_job(self, job_name, job_conf):
        """Schedule a recurring bash job."""
        timing = job_conf.get("timing")
        if not timing:
            print(f"[queue_boss] Task {job_name} has no timing entry, skipping.")
            return

        def parse_interval(timing_str):
            if timing_str.isdigit():
                return int(timing_str)
            units = {'s': 1, 'm': 60, 'h': 3600, 'd': 86400, 'w': 604800}
            for unit, mult in units.items():
                if timing_str.endswith(unit):
                    return int(float(timing_str[:-1]) * mult)
            raise ValueError(f"Cannot parse timing '{timing_str}'")

        interval = parse_interval(timing)
        num_threads = int(job_conf.get('threads', 1))
        timeout = int(job_conf.get("timeout", 900))
        device_tag = self.get_current_endpoint().get("DEVICE")
        lock_tag = job_conf.get("lock_tag", f"{job_name}-lock")
        done_tags = parse_tags(job_conf.get("done_tags", f"{job_name}-done"))
        fail_tags = parse_tags(job_conf.get("fail_tags", f"{job_name}-fail"))

        def task_worker(thread_idx, random_start):
            time.sleep(random_start)
            while True:
                key = f"task-thread-{thread_idx}"
                lock_id = key
                # Only allow run if no lock or lock has expired
                lock_path = queue_lockfile_name(job_name, lock_id)
                run_allowed = True
                if os.path.exists(lock_path):
                    try:
                        with open(lock_path, 'r') as f:
                            lock_data = json.load(f)
                        created = lock_data.get("created")
                        if created:
                            last_dt = datetime.fromisoformat(created)
                            if (datetime.utcnow() - last_dt).total_seconds() < interval:
                                run_allowed = False
                    except Exception:
                        pass
                if run_allowed:
                    digest_id = job_conf.get("logic_digest_id")
                    script_content = self.fetch_logic_script(digest_id)
                    if not script_content:
                        print(f"[queue_boss] No script found for task {job_name}")
                        time.sleep(5)
                        continue
                    # Post lock
                    lock_tags = [lock_tag, job_name, "task"]
                    if device_tag:
                        lock_tags.append(device_tag)
                    self.post_digest(content=lock_id, tags=lock_tags)
                    create_queue_lockfile(job_name, lock_id)
                    print(f"[queue_boss] [task] Running {job_name} (thread {thread_idx})")
                    result = self.bash_executor.run_script(job_name, script_content, job_conf)
                    # Handle result
                    try:
                        output_obj = json.loads(result["stdout"])
                    except Exception:
                        output_obj = {}
                    successful = (result["retcode"] == 0) and output_obj.get("content")
                    if successful:
                        res_tags = done_tags.copy()
                    else:
                        res_tags = fail_tags.copy()
                    if "tags" in output_obj:
                        res_tags += parse_tags(output_obj["tags"])
                    content_b64 = output_obj.get("content", "")
                    try:
                        post_content = base64.b64decode(content_b64).decode("utf-8")
                    except Exception:
                        post_content = "[Invalid base64 result]" if content_b64 else (result["stdout"] or "")
                    self.post_digest(content=post_content, tags=res_tags+[job_name])
                    print(f"[queue_boss] [{job_name}] Task thread {thread_idx} {'success' if successful else 'fail'}, lockfile created and result posted.")

                time.sleep(interval + random.uniform(1, 4))

        # Spawn task threads with some random stagger
        for i in range(num_threads):
            stagger = random.uniform(2, 5) * i
            t = threading.Thread(target=task_worker, args=(i, stagger), daemon=True)
            t.start()

    def get_config_digest(self):
        """
        Fetch the YAML config digest (the agent config) using your single-digest GET probe.
        Returns the YAML text content if found, else None.
        """
        import json
        endpoint = self.get_current_endpoint()
        config_digest_id = endpoint.get('CONFIG_DIGEST_ID')
        node_name = endpoint.get('CONFIG_DIGEST_NODE_NAME', endpoint.get('NODE_NAME',''))
        probe_id = endpoint.get('DIGEST_PROBE_ID')
        probe_key = endpoint.get('DIGEST_PROBE_KEY')
        if not (config_digest_id and probe_id and probe_key):
            print("[queue_boss] No CONFIG_DIGEST, single-digest probe, or probe key configured.")
            return None

        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        payload = {
            "method": "GET",
            "endpoint": f"/digests/{config_digest_id}",
            "digest_id": config_digest_id
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        try:
            print(f"[queue_boss] Pulling config digest: {config_digest_id}")
            resp = requests.post(url, json=payload, headers=headers, timeout=30)
            resp.raise_for_status()
            data = resp.json()
            print("[queue_boss] Config digest API response:")
            print(json.dumps(data, indent=2))
            # Try robust extraction
            content = None
            if "output" in data and isinstance(data["output"], dict):
                output = data["output"]
                if "content" in output:
                    content = output["content"]
                elif "data" in output and isinstance(output["data"], dict) and "content" in output["data"]:
                    content = output["data"]["content"]
            elif "content" in data:
                content = data["content"]
            if not content:
                print("[queue_boss] Could not find YAML content in config digest!")
                return None
            print("[queue_boss] Extracted YAML config (first 200 chars):")
            print(content[:200])
            return content
        except Exception as e:
            print(f"[queue_boss] Failed to fetch config digest: {e}")
            return None

    def _fetch_config_yaml(self):
        """
        Fetch YAML for agent config and parse.
        Returns a Python dict, or None if fetch or parse failed.
        """
        yaml_text = self.get_config_digest()   # Now always a string, never a dict!
        if not yaml_text:
            print("[queue_boss] Could not fetch config digest. Exiting.")
            return None
        try:
            import yaml
            config = yaml.safe_load(yaml_text)
            print("[queue_boss] Parsed agent config YAML.")
            return config
        except Exception as e:
            print(f"[queue_boss] Failed to parse YAML: {e}")
            return None

    def parse_yaml(self, yaml_text):
        try:
            return yaml.safe_load(yaml_text)
        except Exception as e:
            print(f"[queue_boss] YAML parse error: {e}")
            return {}
    def fetch_done_digests(self, done_tag, lookback_s, device_tag):
        """Get backend done digests for the job from this device within lookback window."""
        endpoint = self.get_current_endpoint()
        probe_id = endpoint.get('LISTDIGESTS_PROBE_ID')
        probe_key = endpoint.get('LISTDIGESTS_PROBE_KEY')
        node_name = endpoint.get('LISTDIGESTS_NODE_NAME', endpoint.get('NODE_NAME',''))
        url = f"https://probes-{node_name}.xyzpulseinfra.com/api/probes/{probe_id}/run"
        start_dt = (datetime.utcnow() - datetime.timedelta(seconds=lookback_s)).strftime('%Y-%m-%dT%H:%M:%S')
        params = {"tags": done_tag, "start_date": start_dt, "per_page": 1000}
        payload = {
            "method": "GET",
            "endpoint": "/digests",
            "params": params
        }
        headers = {
            "Content-Type": "application/json",
            "X-PROBE-KEY": probe_key
        }
        resp = requests.post(url, json=payload, headers=headers, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        entries = []
        for k in ('feedentries','digests','output'):
            if k in data and isinstance(data[k], list):
                entries.extend(data[k])
        if not entries and isinstance(data.get('output',None), list):
            entries = data['output']
        if device_tag:
            # Only entries with this device in tags
            return [d for d in entries if device_tag in parse_tags(d.get("tags"))]
        return entries


    def _lock_digest_age_sec(self, lock_digest):
        # Given a lock backend digest {"created": ...}, return age in seconds
        c_time = lock_digest.get("created") or lock_digest.get("created_at")
        if not c_time:
            c_time = lock_digest.get("timestamp")     # handle arbitrary names too
        if not c_time:
            # fallback
            return 1e9
        try:
            return (datetime.utcnow() - datetime.fromisoformat(c_time)).total_seconds()
        except Exception:
            return 1e9  # treat as ancient/expired

if __name__ == "__main__":
    def endpoint_getter():
        cfg_path = os.path.expanduser("~/.kash_stash_config.json")
        with open(cfg_path) as f:
            conf = json.load(f)
        idx = conf.get("last_used_endpoint", 0)
        return conf.get("endpoints", [])[idx]
    boss = QueueBoss(endpoint_getter)
    boss.start()
    while True:
        time.sleep(10)