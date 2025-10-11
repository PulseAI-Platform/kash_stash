import requests
import yaml
import os
import threading
import time
import random
from datetime import datetime, timedelta
import json
import base64
from bash_executor import BashExecutor
from python_executor import PythonExecutor
from powershell_executor import PowerShellExecutor

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


class PodDigestFetcher:
    """Helper class for fetching digests via Pod API"""
    
    def __init__(self, pod_url, pod_key):
        self.pod_url = pod_url.rstrip('/')
        self.pod_key = pod_key
        self.config_cache = {}  # {digest_id: (content, timestamp)}
    
    def fetch_digests_by_tags(self, tags, max_pages=10):
        """
        Fetch all digests for given tags (comma-separated string).
        Handles pagination automatically.
        """
        if isinstance(tags, list):
            tags = ','.join(tags)
        
        all_digests = []
        page = 1
        
        while page <= max_pages:
            try:
                response = requests.get(
                    f"{self.pod_url}/api/pods/digests",
                    params={"tags": tags, "page": page, "per_page": 100},
                    headers={"X-POD-KEY": self.pod_key},
                    timeout=30
                )
                response.raise_for_status()
                
                data = response.json()
                entries = data.get('feedentries', [])
                all_digests.extend(entries)
                
                # Check if more pages
                total_pages = data.get('pages', 1)
                if page >= total_pages or not entries:
                    break
                page += 1
            except Exception as e:
                print(f"[PodFetcher] Error fetching page {page}: {e}")
                break
        
        return all_digests
    
    def fetch_digest_by_id(self, digest_id, search_tags, use_cache=True, cache_minutes=5):
        """
        Fetch a specific digest by ID, searching within the provided tags.
        Implements caching based on cache_minutes setting.
        """
        # Check cache
        if use_cache and cache_minutes != 0:
            cached = self.config_cache.get(digest_id)
            if cached:
                content, timestamp = cached
                age_minutes = (datetime.now() - timestamp).seconds / 60
                
                if cache_minutes == -1 or age_minutes < cache_minutes:
                    print(f"[PodFetcher] Using cached content for {digest_id} (age: {age_minutes:.1f} min)")
                    return content
        
        # Fetch fresh
        print(f"[PodFetcher] Fetching digest {digest_id} from tags: {search_tags}")
        digests = self.fetch_digests_by_tags(search_tags)
        
        for entry in digests:
            if str(entry.get('id')) == str(digest_id):
                content = entry.get('content', '')
                
                # Update cache
                if cache_minutes != 0:
                    self.config_cache[digest_id] = (content, datetime.now())
                
                return content
        
        raise ValueError(f"Digest {digest_id} not found in tags: {search_tags}")
    
    def fetch_digests_with_lookback(self, tags, lookback_seconds):
        digests = self.fetch_digests_by_tags(tags)
        print(f"[DEBUG] fetch_digests_with_lookback: Got {len(digests)} digests for tags '{tags}'")
        
        cutoff = datetime.utcnow() - timedelta(seconds=lookback_seconds)
        filtered = []
        
        for entry in digests:
            timestamp_str = (entry.get('created_at') or 
                        entry.get('created') or 
                        entry.get('timestamp'))
            
            if timestamp_str:
                try:
                    if timestamp_str.endswith('Z'):
                        timestamp_str = timestamp_str[:-1] + '+00:00'
                    timestamp = datetime.fromisoformat(timestamp_str)
                    if timestamp >= cutoff:
                        filtered.append(entry)
                except Exception as e:
                    print(f"[DEBUG] Could not parse timestamp for digest {entry.get('id')}: {timestamp_str} - {e}")
                    filtered.append(entry)  # Include it if we can't parse
            else:
                print(f"[DEBUG] Digest {entry.get('id')} has no timestamp field, including it")
                filtered.append(entry)
        
        print(f"[DEBUG] After lookback filter: {len(filtered)} digests remain")
        return filtered


class QueueBoss:
    def __init__(self, endpoint_getter):
        self.bash_executor = BashExecutor()
        self.python_executor = PythonExecutor()
        self.powershell_executor = PowerShellExecutor()
        self.get_current_endpoint = endpoint_getter
        self.pod_fetcher = None
        self._init_pod_fetcher()
    
    def _init_pod_fetcher(self):
        """Initialize pod fetcher if pod config exists"""
        endpoint = self.get_current_endpoint()
        if endpoint and endpoint.get('POD_URL') and endpoint.get('POD_KEY'):
            self.pod_fetcher = PodDigestFetcher(
                endpoint['POD_URL'],
                endpoint['POD_KEY']
            )
            print(f"[queue_boss] Initialized pod fetcher for {endpoint['POD_URL']}")
    
    def get_executor_for_language(self, language):
        """Get the appropriate executor for the job language"""
        language = language.lower()  # Normalize
        if language in ('bash', 'sh'):
            return self.bash_executor
        elif language in ('python', 'python3', 'py'):
            return self.python_executor
        elif language in ('powershell', 'pwsh', 'ps1'):
            return self.powershell_executor
        else:
            raise ValueError(f"Unsupported language: {language}")
    
    def _now_iso(self):
        return datetime.utcnow().isoformat()

    def get_config_digest(self):
        """Fetch config YAML using pod API"""
        endpoint = self.get_current_endpoint()
        config_id = endpoint.get('CONFIG_DIGEST_ID')
        config_tags = endpoint.get('CONFIG_DIGEST_TAGS', 'agent-config')
        cache_minutes = endpoint.get('CONFIG_CACHE_MINUTES', 5)
        
        if not (self.pod_fetcher and config_id):
            print("[queue_boss] No pod config or config digest ID")
            return None
        
        try:
            content = self.pod_fetcher.fetch_digest_by_id(
                config_id,
                config_tags,
                use_cache=True,
                cache_minutes=cache_minutes
            )
            return content
        except Exception as e:
            print(f"[queue_boss] Failed to fetch config: {e}")
            return None

    def fetch_logic_script(self, digest_id):
        """Fetch logic script by ID using pod API"""
        if not self.pod_fetcher:
            print("[queue_boss] No pod configured")
            return None
        
        endpoint = self.get_current_endpoint()
        # Use CONFIG_DIGEST_TAGS as the search space for scripts
        # Scripts are usually in the same tags as configs
        script_tags = endpoint.get('CONFIG_DIGEST_TAGS', 'agent-config')
        
        try:
            content = self.pod_fetcher.fetch_digest_by_id(
                digest_id,
                script_tags,
                use_cache=False  # Don't cache logic scripts
            )
            print(f"[queue_boss] Fetched logic script {digest_id} (first 200 chars):")
            print(content[:200] if content else "Empty")
            return content
        except Exception as e:
            print(f"[queue_boss] Failed to fetch logic script {digest_id}: {e}")
            return None

    def fetch_queue_digests(self, queue_tag, lookback_s):
        """Fetch queue digests using pod API - uses job-specific queue tag"""
        if not self.pod_fetcher:
            raise RuntimeError("Pod not configured!")
        
        # Just use the queue_tag from the job config directly
        return self.pod_fetcher.fetch_digests_with_lookback(queue_tag, lookback_s)

    def fetch_lock_digests(self, lock_tag, lookback_s, device_tag):
        """Fetch lock digests using pod API - uses job-specific lock tag"""
        if not self.pod_fetcher:
            raise RuntimeError("Pod not configured!")
        
        # Just use the lock_tag from the job config directly
        digests = self.pod_fetcher.fetch_digests_with_lookback(lock_tag, lookback_s)
        
        # NO DEVICE FILTERING - return all lock digests regardless of device
        # This allows cross-agent locking to work properly
        return digests

    def fetch_done_digests(self, done_tag, lookback_s, device_tag):
        """Get backend done digests for the job within lookback window - uses job-specific done tag"""
        if not self.pod_fetcher:
            raise RuntimeError("Pod not configured!")
        
        # Just use the done_tag from the job config directly
        digests = self.pod_fetcher.fetch_digests_with_lookback(done_tag, lookback_s)
        
        # NO DEVICE FILTERING - return all done digests regardless of device
        # If work was done by ANY agent, it's done
        return digests

    def fetch_fail_digests(self, fail_tag, lookback_s, device_tag):
        """Fetch failure digests using pod API - uses job-specific fail tag"""
        if not self.pod_fetcher:
            raise RuntimeError("Pod not configured!")
        
        # Just use the fail_tag from the job config directly
        digests = self.pod_fetcher.fetch_digests_with_lookback(fail_tag, lookback_s)
        
        # NO DEVICE FILTERING - return all fail digests regardless of device
        # If work failed on ANY agent, it failed
        return digests

    def post_digest(self, content, tags, filename=None, context_prompt=None):
        """
        Post a text digest as a file (base64), matching user/desktop uploader format.
        Still uses POST probe via API bastion.
        """
        endpoint = self.get_current_endpoint()
        probe_id = endpoint.get('PROBE_ID')
        node_name = endpoint.get('NODE_NAME')
        probe_key = endpoint.get('PROBE_KEY')
        
        if filename is None:
            filename = f"agent_output_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.txt"
        
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

        # Validate required tags
        if not queue_tag:
            print(f"[queue_boss] ERROR: Queue job {job_name} has no queue_tag defined!")
            return

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
            # Define separate lookback windows
            LOCK_DONE_LOOKBACK = 86400  # 24 hours for lock/done digests
            
            while True:
                try:
                    digests = self.fetch_queue_digests(queue_tag, lookback_s)
                    
                    if not digests:
                        time.sleep(3)
                        continue

                    # === Backend lock and done digests for device ===
                    lock_digests_list = self.fetch_lock_digests(lock_tag, LOCK_DONE_LOOKBACK, device_tag=device_tag)
                    done_digests_list = self.fetch_done_digests(done_tags[0] if done_tags else '', LOCK_DONE_LOOKBACK, device_tag=device_tag)
                    print(f"[queue_boss DEBUG] Thread {thread_id}: Found {len(done_digests_list)} done digests after fetch")

                    # Map digest id -> lock digest
                    locked_map = {}
                    for d in lock_digests_list:
                        content_id = str(d.get('content', '')).strip()
                        if content_id:
                            locked_map[content_id] = d

                    # Extract done IDs from tags - look for done digests that ALSO have processed-{id} tag
                    done_ids = set()
                    for d in done_digests_list:
                        # Check if this done digest has tags field
                        tags_field = d.get("tags", "")
                        
                        # Parse tags - could be string or list
                        if isinstance(tags_field, str):
                            tags = parse_tags(tags_field)
                        elif isinstance(tags_field, list):
                            tags = tags_field
                        else:
                            tags = []
                        
                        # Look for processed-{id} tag in this done digest
                        for tag in tags:
                            # Handle tag as dict or string
                            if isinstance(tag, dict):
                                tag_name = tag.get('name', '')
                            else:
                                tag_name = str(tag)
                            
                            if tag_name.startswith("processed-"):
                                done_id = tag_name[10:]  # Remove "processed-" prefix
                                done_ids.add(done_id)

                    # Find candidate work
                    work = []
                    for d in digests:
                        digest_id = str(d['id'])
                        
                        # Skip if already done
                        if digest_id in done_ids:
                            continue

                        # Skip if backend locked
                        if digest_id in locked_map:
                            lock_age = self._lock_digest_age_sec(locked_map[digest_id])
                            print(f"[queue_boss DEBUG] Thread {thread_id}: Digest {digest_id} is locked, age: {lock_age:.0f}s")
                            if lock_age < timeout:
                                print(f"[queue_boss] Thread {thread_id}: Digest {digest_id} backend locked (age: {lock_age:.0f}s < timeout: {timeout}s)")
                                continue
                            else:
                                print(f"[queue_boss] Thread {thread_id}: Digest {digest_id} backend lock stale (age: {lock_age:.0f}s > timeout: {timeout}s)")

                        # Skip if locally locked (PERMANENT lockfile check)
                        lockfile_path = queue_lockfile_name(job_name, digest_id)
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Checking lockfile: {lockfile_path}")
                        if os.path.exists(lockfile_path):
                            print(f"[queue_boss] Thread {thread_id}: Digest {digest_id} has lockfile (already processed), skipping")
                            continue

                        # This digest is available for work
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Adding digest {digest_id} to work queue")
                        work.append(d)

                    if not work:
                        print(f"[queue_boss] ({job_name}) Thread {thread_id}: No unlocked/undone queue digests in lookback ({lookback})")
                        time.sleep(5)
                        continue

                    print(f"[queue_boss DEBUG] Thread {thread_id}: Processing {len(work)} work items")
                    
                    # Process work items one at a time with immediate locking
                    for d in work:
                        digest_id = str(d['id'])
                        
                        # CRITICAL: Atomic check-and-create for lockfile
                        lockfile_path = queue_lockfile_name(job_name, digest_id)
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Attempting to create lockfile atomically for {digest_id} at {lockfile_path}")
                        
                        try:
                            # Use os.open with O_CREAT | O_EXCL for atomic creation
                            fd = os.open(lockfile_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                            # If we get here, we successfully created the file atomically
                            lock_data = json.dumps({
                                "created": datetime.utcnow().isoformat(),
                                "thread": thread_id,
                                "info": {}
                            })
                            os.write(fd, lock_data.encode())
                            os.close(fd)
                            print(f"[queue_boss DEBUG] Thread {thread_id}: Successfully created lockfile for {digest_id}")
                        except FileExistsError:
                            print(f"[queue_boss] Thread {thread_id}: Lockfile already exists for {digest_id} (another thread got it), skipping")
                            continue
                        except Exception as e:
                            print(f"[queue_boss DEBUG] Thread {thread_id}: Failed to create lockfile: {e}")
                            continue
                        
                        # Re-fetch recent locks to see if another thread just locked it
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Re-fetching recent locks before claiming {digest_id}")
                        fresh_locks = self.fetch_lock_digests(lock_tag, 60, device_tag=device_tag)  # Last 60 seconds
                        fresh_locked_ids = {str(ld.get('content', '')).strip() for ld in fresh_locks}
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Fresh locked IDs: {fresh_locked_ids}")
                        
                        if digest_id in fresh_locked_ids:
                            print(f"[queue_boss] Thread {thread_id}: Digest {digest_id} just got backend locked by another thread, keeping our lockfile to prevent future processing")
                            continue
                        
                        # Also re-check done status
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Re-fetching recent done digests before claiming {digest_id}")
                        fresh_done = self.fetch_done_digests(done_tags[0] if done_tags else '', 60, device_tag=device_tag)  # Last 60 seconds
                        fresh_done_ids = set()
                        for dd in fresh_done:
                            tags_field = dd.get("tags", "")
                            if isinstance(tags_field, str):
                                tags = parse_tags(tags_field)
                            elif isinstance(tags_field, list):
                                tags = tags_field
                            else:
                                tags = []
                            
                            for tag in tags:
                                if isinstance(tag, dict):
                                    tag_name = tag.get('name', '')
                                else:
                                    tag_name = str(tag)
                                
                                if tag_name == f"processed-{digest_id}":
                                    fresh_done_ids.add(digest_id)
                                    print(f"[queue_boss] Thread {thread_id}: Digest {digest_id} just got processed by another thread, keeping our lockfile to prevent future processing")
                                    break
                        
                        if digest_id in fresh_done_ids:
                            continue
                        
                        # NOW we can claim this work - post backend lock
                        print(f"[queue_boss] Thread {thread_id}: Claiming digest {digest_id} - posting backend lock")
                        
                        # Post backend lock
                        lock_tags = [lock_tag, job_name]
                        if device_tag: 
                            lock_tags.append(device_tag)
                        lock_result = self.post_digest(content=str(digest_id), tags=",".join(lock_tags))
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Backend lock post result: {lock_result}")
                        
                        # --------- actual business logic run ---------
                        logic_digest_id = job_conf.get("logic_digest_id")
                        if not logic_digest_id:
                            print(f"[queue_boss] ERROR: No logic_digest_id for queue job {job_name}")
                            continue
                            
                        script = self.fetch_logic_script(logic_digest_id)
                        if not script:
                            print(f"[queue_boss] Could not fetch script for queue job {job_name}")
                            print(f"[queue_boss DEBUG] Thread {thread_id}: Keeping lockfile for {digest_id} despite script fetch failure")
                            continue
                        
                        digest_content_input = d.get("content", "")
                        input_file = None
                        if digest_content_input:
                            import tempfile
                            input_file = tempfile.NamedTemporaryFile(delete=False)
                            input_file.write(digest_content_input.encode('utf-8'))
                            input_file.close()
                        
                        # Get the right executor based on language
                        language = job_conf.get('language', 'bash')
                        try:
                            executor = self.get_executor_for_language(language)
                        except ValueError as e:
                            print(f"[queue_boss] {e} for job {job_name}")
                            if input_file:
                                os.unlink(input_file.name)
                            continue
                        
                        print(f"[queue_boss] ({job_name}) Thread {thread_id} executing digest {digest_id} with {language}")
                        result = executor.run_script(
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
                        
                        # Add processed-{id} tag to track completion
                        res_tags.append(f"processed-{digest_id}")
                        
                        if "tags" in output_obj:
                            res_tags += parse_tags(output_obj["tags"])
                        
                        res_tags.append(job_name)
                        
                        content_b64 = output_obj.get("content", "")
                        try:
                            post_content = base64.b64decode(content_b64).decode("utf-8")
                        except Exception:
                            post_content = "[Invalid base64 result]" if content_b64 else (result["stdout"] or "")
                        
                        print(f"[queue_boss] Thread {thread_id}: Posting result for digest {digest_id} with tags: {','.join(res_tags)}")
                        result_post = self.post_digest(content=post_content, tags=",".join(res_tags))
                        print(f"[queue_boss DEBUG] Thread {thread_id}: Result post response: {result_post}")
                        
                        # CRITICAL FIX: DON'T REMOVE THE LOCKFILE!
                        # The lockfile serves as permanent record that this digest was processed
                        print(f"[queue_boss DEBUG] Thread {thread_id}: KEEPING lockfile for {digest_id} to prevent any future reprocessing")
                        
                        # Add stagger between processing items
                        time.sleep(random_stagger(thread_id))
                        
                except Exception as e:
                    print(f"[queue_boss] Exception in queue job worker {job_name} thread {thread_id}: {e}")
                    import traceback
                    traceback.print_exc()
                    time.sleep(5)
            
        # CREATE THE WORKER THREADS
        for i in range(threads):
            t = threading.Thread(target=worker_loop, args=(i,), daemon=True, name=f"{job_name}-worker-{i}")
            t.start()
            print(f"[queue_boss] Started queue worker thread {i} for job {job_name}")

    def start(self):
        ensure_lock_dir()
        
        def config_monitor():
            last_config_fetch = None
            running_jobs = {}  # Track which jobs are already running
            
            while True:
                # Check if it's time to refresh config
                endpoint = self.get_current_endpoint()
                cache_minutes = endpoint.get('CONFIG_CACHE_MINUTES', 5)
                
                # Determine if we should fetch config
                should_fetch = False
                if last_config_fetch is None:
                    # First run
                    should_fetch = True
                elif cache_minutes == 0:
                    # Always refresh (every loop iteration, with a small delay)
                    should_fetch = True
                elif cache_minutes == -1:
                    # Never refresh after initial load
                    should_fetch = False
                else:
                    # Check if cache expired
                    age_minutes = (datetime.now() - last_config_fetch).total_seconds() / 60
                    if age_minutes >= cache_minutes:
                        should_fetch = True
                
                if should_fetch:
                    print(f"[queue_boss] Fetching config (cache_minutes={cache_minutes})...")
                    
                    # Re-init pod fetcher in case config changed
                    self._init_pod_fetcher()
                    
                    # Clear config cache to force fresh fetch
                    if self.pod_fetcher and hasattr(self.pod_fetcher, 'config_cache'):
                        self.pod_fetcher.config_cache.clear()
                    
                    config_digest = self._fetch_config_yaml()
                    if not config_digest:
                        print("[queue_boss] Could not fetch config digest. Retrying in 60s...")
                        time.sleep(60)
                        continue
                    
                    last_config_fetch = datetime.now()
                    config = config_digest
                    
                    # Process all jobs in config
                    for name, job in config.items():
                        if not isinstance(job, dict) or 'type' not in job or 'job' not in job:
                            print(f"[queue_boss] Skipping invalid job entry '{name}' (missing type/job)")
                            continue
                        
                        job_type = job['type']
                        job_conf = job['job']
                        language = job_conf.get('language', 'bash')
                        
                        # Check if language is supported
                        if language.lower() not in ('bash', 'sh', 'python', 'python3', 'py', 'powershell', 'pwsh', 'ps1'):
                            print(f"[queue_boss] Unsupported language '{language}' for job {name}")
                            continue
                        
                        # Check if this job is already running
                        job_key = f"{name}:{job_type}"
                        if job_key in running_jobs:
                            # Job already running, skip
                            continue
                        
                        # Start the job based on type
                        if job_type in ('setup', 'onetime'):
                            t = threading.Thread(
                                target=self.run_setup_or_onetime, 
                                args=(name, job_conf, job_type), 
                                daemon=True
                            )
                            t.start()
                            # Don't mark setup/onetime as permanently running
                            # They complete and won't restart until lockfile is removed
                            
                        elif job_type == 'task':
                            print(f"[queue_boss] Starting task job: {name} ({language})")
                            self.schedule_task_job(name, job_conf)
                            running_jobs[job_key] = True
                            
                        elif job_type == 'queue':
                            if not self.pod_fetcher:
                                print(f"[queue_boss] ERROR: Queue job {name} requires pod configuration! Skipping.")
                                continue
                            print(f"[queue_boss] Starting queue job thread(s) for {name} ({language})")
                            self.process_queue_job(name, job_conf)
                            running_jobs[job_key] = True
                            
                        else:
                            print(f"[queue_boss] Unknown job type {job_type} for job {name}")
                    
                    # Check for removed jobs (jobs that were in running_jobs but not in new config)
                    current_job_keys = {f"{name}:{job['type']}" 
                                    for name, job in config.items() 
                                    if isinstance(job, dict) and 'type' in job}
                    removed_jobs = set(running_jobs.keys()) - current_job_keys
                    if removed_jobs:
                        print(f"[queue_boss] Warning: Jobs removed from config but still running: {removed_jobs}")
                        # Note: We can't easily stop running threads, they'll keep running
                        # until the process restarts
                
                # Sleep before next check
                if cache_minutes == 0:
                    time.sleep(30)  # Check every 30 seconds for "always refresh"
                elif cache_minutes == -1:
                    time.sleep(3600)  # Check hourly for "never refresh" (just in case)
                else:
                    # Sleep for 1 minute, will check if cache expired on next iteration
                    time.sleep(60)
        
        # Start the config monitor in its own thread
        monitor_thread = threading.Thread(target=config_monitor, daemon=True, name="ConfigMonitor")
        monitor_thread.start()
        print("[queue_boss] Config monitor started")

    def run_setup_or_onetime(self, job_name, job_conf, job_type):
        """Run a setup or onetime job if no lockfile exists/left behind; creates lockfile after run."""
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
        self.post_digest(content="setup", tags=",".join(lock_tags))
        create_queue_lockfile(job_name, "setup")

        # Get the right executor
        language = job_conf.get('language', 'bash')
        try:
            executor = self.get_executor_for_language(language)
        except ValueError as e:
            print(f"[queue_boss] {e} for job {job_name}")
            return

        # Run the script
        print(f"[queue_boss] Running {job_type} {language} job {job_name}")
        result = executor.run_script(job_name, script_content, job_conf)

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
        res_tags.append(job_name)
        self.post_digest(content=post_content, tags=",".join(res_tags))
        print(f"[queue_boss] [{job_name}] Setup/Onetime {('success' if successful else 'fail')}, lockfile created and result posted.")

    def schedule_task_job(self, job_name, job_conf):
        """Schedule a recurring job."""
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
                    
                    # Get the right executor
                    language = job_conf.get('language', 'bash')
                    try:
                        executor = self.get_executor_for_language(language)
                    except ValueError as e:
                        print(f"[queue_boss] {e} for task {job_name}")
                        time.sleep(5)
                        continue
                    
                    # Tasks only need local lockfiles, not backend locks
                    create_queue_lockfile(job_name, lock_id)
                    
                    print(f"[queue_boss] [task] Running {job_name} (thread {thread_idx}) with {language}")
                    result = executor.run_script(job_name, script_content, job_conf)
                    
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
                    res_tags.append(job_name)
                    self.post_digest(content=post_content, tags=",".join(res_tags))
                    print(f"[queue_boss] [{job_name}] Task thread {thread_idx} {'success' if successful else 'fail'}, lockfile created and result posted.")

                time.sleep(interval + random.uniform(1, 4))

        # Spawn task threads with some random stagger
        for i in range(num_threads):
            stagger = random.uniform(2, 5) * i
            t = threading.Thread(target=task_worker, args=(i, stagger), daemon=True)
            t.start()

    def _fetch_config_yaml(self):
        """
        Fetch YAML for agent config and parse.
        Returns a Python dict, or None if fetch or parse failed.
        """
        yaml_text = self.get_config_digest()
        if not yaml_text:
            print("[queue_boss] Could not fetch config digest. Exiting.")
            return None
        try:
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