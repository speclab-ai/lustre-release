# Simulator Refactoring TODO: Extracting General-Purpose Infra Library

This document outlines the plan for extracting a reusable, general-purpose distributed systems simulation infrastructure library from the current KV store simulator.

## Goals

1. **Extract reusable patterns** into `infra/` that can be used for simulating any distributed system
2. **Keep domain-specific logic** (KV store, sharding, etc.) in the application layer (`components/`, `models/`)
3. **Improve modularity, testability, and observability** across all simulators built on this infra

## Current State

### Already in `infra/` (Good Foundation)
- ✅ `machine.py` - Machine abstraction with fail/recover, clock skew
- ✅ `network.py` - Message passing, latency simulation, network failures
- ✅ `availability_zone.py` - AZ-level fault domains
- ✅ `load_balancer.py` - Basic load balancing

### Common Patterns to Extract (High Priority)

These patterns appear across multiple components and are general-purpose:

#### 1. Base Service/Component Class
**Location:** `infra/base_service.py` (new)

**Phase:** Phase 1 (Pure Refactoring)

**Rationale:** GatewayNode, DataNode, ClientLibrary all implement identical crash/recovery and message listening patterns. Extract this existing code.

**What already exists (extract these):**
- `crash()` / `recover()` methods in GatewayNode:63-73, DataNode:90-105
- `is_crashed` field in both components
- `_listen_for_messages()` pattern in GatewayNode:75-89, DataNode (similar)
- `_on_machine_fail()` / `_on_machine_recover()` callbacks in both
- Machine callback registration in both

**Usage pattern:**
```python
class BaseService(BaseModel):
    id: str
    env: simpy.Environment
    network: Network
    machine: Machine
    is_crashed: bool = False
    _listen_process: Optional[simpy.Process] = None

    def crash(self): ...
    def recover(self): ...
    def _listen_for_messages(self): ...  # Can be overridden
    def _handle_message(self, msg: NetworkMessage): ...  # Must be implemented by subclass
```

**Priority:** ⭐⭐⭐ PHASE 1 - Pure extraction, no new features

---

#### 2. Request Tracing & Context Management
**Location:** `infra/request_context.py` (move existing)

**Phase:** Phase 1 for move, Phase 3 for new utilities

**Rationale:** RequestContext already exists in `models/internal.py:50-52` but should be in infra since it's generic.

**Phase 1 (Refactoring):**
- Move existing `RequestContext` class from `models/internal.py` to `infra/request_context.py`
- Update all imports
- **NO new functionality**

**Phase 3 (New Features):**
- Add UUID-based request ID generation utility (**NEW**)
- Add RequestContext factory/builder (**NEW**)
- Add context propagation helpers (**NEW**)

**Example API (Phase 3):**
```python
# NEW utilities in Phase 3
def generate_request_id() -> str:
    return str(uuid.uuid4())

def create_request_context(request_id: Optional[str] = None, **kwargs) -> RequestContext:
    return RequestContext(request_id=request_id or generate_request_id(), **kwargs)
```

**Priority:** ⭐⭐⭐ PHASE 1 (move), PHASE 3 (new utilities)

---

#### 3. Logging Utilities with Context
**Location:** `infra/logger.py` (new)

**Phase:** Phase 1 (Pure Refactoring)

**Rationale:** `_get_log_prefix()` is duplicated in GatewayNode:46-49 and DataNode:51-54 with **identical** implementation. Extract to eliminate duplication.

**What already exists (extract this):**
- `_get_log_prefix()` method in both GatewayNode and DataNode
- Same logic: format timestamp with machine clock skew
- Same logic: include request_id if present
- Same format string pattern

**What to extract:**
```python
# Extract from GatewayNode:46-49 and DataNode:51-54
class ContextLogger:
    def __init__(self, component_id: str, machine: Machine, env: simpy.Environment):
        self.component_id = component_id
        self.machine = machine
        self.env = env

    def info(self, msg: str, request_context: Optional[RequestContext] = None):
        prefix = self._get_prefix(request_context)
        logger.info(f"{prefix} {msg}")

    def _get_prefix(self, request_context: Optional[RequestContext]) -> str:
        # EXACT same logic as existing _get_log_prefix()
        timestamp = self.machine.get_current_time(self.env.now)
        base = f"[{timestamp:.4f}] {self.component_id}"
        if request_context and request_context.request_id:
            return f"{base} [ReqID: {request_context.request_id}]"
        return base
```

**Priority:** ⭐⭐⭐ PHASE 1 - Pure extraction of duplicated code

---

#### 4. Metrics & Observability
**Location:** `infra/metrics.py` (move from `models/`)

**Phase:** Phase 1 for move, Phase 3 for new features

**Rationale:** MetricsCollector already exists in `models/metrics.py:11-30` and is generic enough for any distributed system.

**Phase 1 (Refactoring):**
- Move existing `MetricsCollector` from `models/metrics.py` to `infra/metrics.py`
- Move existing `ErrorCategory` enum
- Update all imports (GatewayNode:14, DataNode:11)
- **NO changes to functionality**

**Phase 3 (New Features):**
- Create new `Tracer` class for enhanced latency tracking (**NEW**)
- Add latency aggregation (percentiles, histograms) (**NEW**)
- Add throughput tracking (**NEW**)

**Example new features (Phase 3):**
```python
# NEW in Phase 3
class Tracer:
    """Records timestamped events for request lifecycle analysis"""
    def __init__(self, env: simpy.Environment):
        self.env = env
        self.traces: Dict[str, List[Tuple[float, str, str]]] = {}

    def record_event(self, request_id: str, operation: str, component_id: str):
        if request_id not in self.traces:
            self.traces[request_id] = []
        self.traces[request_id].append((self.env.now, operation, component_id))

    def get_latency(self, request_id: str, start_op: str, end_op: str) -> Optional[float]:
        """Calculate latency between two operations"""
        ...
```

**Priority:** ⭐⭐⭐ PHASE 1 (move), PHASE 3 (new features)

---

#### 5. Fault Injection Framework
**Location:** `infra/fault_injector.py` (new)

**Phase:** Phase 4 (New Feature)

**Rationale:** Currently failures are triggered manually throughout the codebase. A centralized fault injector enables complex failure scenarios. **This is entirely new functionality.**

**What exists today:**
- Manual `machine.fail()` / `machine.recover()` calls
- Manual `network.fail_link()` / `network.fail_az_network()` calls
- No centralized coordination
- No scenario definition capability

**What Phase 4 adds (NEW):**
- Unified API for triggering failures across components
- Support for failure scenarios (sequences of coordinated failures)
- Declarative scenario definitions
- Time-based failure injection
- Additional network failure modes (corruption, jitter)

**Example API (Phase 4):**
```python
# NEW in Phase 4
class FaultInjector:
    def __init__(self, env: simpy.Environment, network: Network):
        self.env = env
        self.network = network
        self.machines: Dict[str, Machine] = {}
        self.azs: Dict[str, AvailabilityZone] = {}

    def crash_machine(self, machine_id: str, duration: Optional[float] = None):
        """Crash a machine, optionally recovering after duration"""
        ...

    def partition_network(self, az1: str, az2: str, duration: float):
        """Create network partition between AZs"""
        ...

    def inject_latency(self, from_node: str, to_node: str, added_latency: float, duration: float):
        """Add latency to specific link"""
        ...

    def run_scenario(self, scenario: FailureScenario):
        """Execute a complex failure scenario"""
        ...
```

**Priority:** PHASE 4 - New feature for sophisticated fault testing

---

### Resource Modeling (Advanced Phase)

These features add realistic resource constraints to the simulation, enabling performance testing and capacity planning scenarios:

#### 6. CPU Resource Management
**Location:** Extend `infra/machine.py`, create `infra/resource_manager.py`

**Rationale:** Real distributed systems are CPU-bound. Modeling CPU enables testing of resource contention, load shedding, and performance under stress.

**Features:**
- `cpu_capacity` attribute on Machine (e.g., CPU units, cores, or cycles per second)
- SimPy `Resource` or `Container` for CPU allocation
- `CPUResourceManager` to track CPU usage across processes on a machine
- Components request CPU time for operations (processing requests, serialization, compression)
- Backpressure/throttling when CPU exhausted (queue requests, shed load, or increase latency)
- CPU usage metrics (utilization %, saturation)

**Example API:**
```python
class Machine(BaseModel):
    cpu_capacity: float = 100.0  # CPU units (cores * clock speed normalized)
    _cpu_resource: simpy.Container  # Tracks available CPU

class BaseService:
    def consume_cpu(self, amount: float, operation: str):
        """Request CPU for an operation, blocks if unavailable"""
        yield self.machine._cpu_resource.get(amount)
        # Simulate processing time
        processing_time = amount / self.machine.cpu_capacity
        yield self.env.timeout(processing_time)
        # Release CPU
        yield self.machine._cpu_resource.put(amount)

# In DataNode
def _handle_put(self, msg):
    # Consume CPU for request processing
    yield from self.consume_cpu(amount=5.0, operation="put_processing")
    # ... rest of logic
```

**Priority:** ⭐⭐ MEDIUM-HIGH - Critical for realistic performance modeling

---

#### 7. Disk Resource Management
**Location:** Extend `infra/machine.py`, create `infra/disk.py`

**Rationale:** Storage systems are constrained by disk capacity, throughput (MB/s), and IOPS. Essential for testing behavior under disk pressure.

**Features:**

**Disk Capacity:**
- `disk_capacity` attribute (total bytes available)
- `disk_used` tracking (current usage)
- Write operations fail/block when disk full
- Configurable behavior: fail fast vs. block vs. evict old data

**Disk Throughput (MB/s):**
- `disk_throughput_limit` (bytes per second)
- Track cumulative bytes written/read per time window
- Throttle I/O operations when throughput exceeded
- Separate read/write throughput limits

**Disk IOPS (operations per second):**
- `disk_iops_limit` (operations per second)
- Track I/O operations per time window
- Queue or delay operations when IOPS limit reached
- Separate random vs. sequential I/O costs

**Example API:**
```python
class DiskResource(BaseModel):
    """Represents a disk with capacity and performance limits"""
    capacity: float  # Total bytes
    used: float = 0.0  # Current usage
    throughput_limit: float = 100_000_000  # 100 MB/s
    read_iops_limit: float = 1000  # ops/sec
    write_iops_limit: float = 500  # ops/sec

    _throughput_window: List[Tuple[float, float]] = []  # (timestamp, bytes)
    _iops_window: List[Tuple[float, str]] = []  # (timestamp, operation_type)

    def write(self, env: simpy.Environment, data_size: float):
        """Write data to disk, respecting capacity, throughput, and IOPS limits"""
        # Check capacity
        if self.used + data_size > self.capacity:
            raise DiskFullError(f"Disk full: {self.used}/{self.capacity} bytes used")

        # Wait for IOPS availability
        yield from self._wait_for_iops(env, "write")

        # Wait for throughput availability
        yield from self._wait_for_throughput(env, data_size)

        # Perform write (simulate latency)
        write_latency = data_size / self.throughput_limit
        yield env.timeout(write_latency)

        self.used += data_size
        self._record_operation(env.now, "write", data_size)

    def read(self, env: simpy.Environment, data_size: float):
        """Read data from disk, respecting throughput and IOPS limits"""
        # Similar to write but no capacity check
        ...

class Machine(BaseModel):
    disk: Optional[DiskResource] = None

    def __init__(self, **data):
        super().__init__(**data)
        if self.disk is None:
            self.disk = DiskResource(capacity=1_000_000_000)  # 1GB default
```

**Usage in DataNode:**
```python
def _handle_put(self, msg: NetworkMessage):
    put_req = msg.payload
    data_size = len(put_req.value.encode('utf-8'))

    # Write to WAL (sequential write, disk I/O)
    yield from self.machine.disk.write(self.env, data_size)

    # Update in-memory KV store
    self.kv_store[put_req.key] = KVEntry(value=put_req.value, ...)
```

**Priority:** ⭐⭐ MEDIUM-HIGH - Essential for storage system simulations

---

#### 8. Network Bandwidth & IOPS Limits
**Location:** Extend `infra/network.py`

**Rationale:** Network is often the bottleneck in distributed systems. Modeling bandwidth and packet rates enables testing of network saturation, queuing, and congestion.

**Features:**

**Bandwidth Limits (bytes/sec):**
- Per-link bandwidth limits (e.g., 1 Gbps = 125 MB/s)
- Per-AZ bandwidth limits (aggregate)
- Track bytes in flight across time windows
- Queue or drop messages when bandwidth exceeded

**IOPS/Packet Rate Limits (packets/sec):**
- Maximum packets per second per link/node/AZ
- Small messages can saturate packet rate before bandwidth
- Queue messages when packet rate exceeded

**Message Size:**
- Add `size` attribute to `NetworkMessage`
- Calculate size based on payload type and content
- Accurate bandwidth consumption modeling

**Queuing and Congestion:**
- Message queues when bandwidth/IOPS limits reached
- Configurable queue depths (drop when queue full)
- Congestion metrics (queue depth, drop rate)

**Example API:**
```python
class NetworkLink(BaseModel):
    """Represents a network link between two nodes or AZs"""
    link_id: str
    bandwidth_limit: float = 125_000_000  # 125 MB/s (1 Gbps)
    packet_rate_limit: float = 10_000  # 10k packets/sec
    queue_depth_limit: int = 1000  # Max queued messages

    _message_queue: List[NetworkMessage] = []
    _bandwidth_window: List[Tuple[float, float]] = []  # (timestamp, bytes)
    _packet_window: List[Tuple[float, int]] = []  # (timestamp, packet_count)

class Network:
    def __init__(self, env, ...):
        self.env = env
        self.links: Dict[Tuple[str, str], NetworkLink] = {}  # (sender, receiver) -> link
        self.az_links: Dict[Tuple[str, str], NetworkLink] = {}  # (az1, az2) -> link

    def send_message(self, message: NetworkMessage):
        # Determine which link to use
        link = self._get_link(message.sender_id, message.receiver_id)

        # Calculate message size
        message.size = self._calculate_message_size(message.payload)

        # Check bandwidth and packet rate limits
        if not link.can_send(self.env.now, message.size):
            if len(link._message_queue) >= link.queue_depth_limit:
                # Drop message due to congestion
                logger.warning(f"Message dropped due to network congestion on {link.link_id}")
                message.dropped = True
                return
            else:
                # Queue message
                link._message_queue.append(message)
                self.env.process(self._process_queue(link))
                return

        # Send immediately
        link.record_transmission(self.env.now, message.size)
        yield from self._deliver_with_bandwidth_delay(message, link)

    def _calculate_message_size(self, payload: Any) -> float:
        """Calculate message size based on payload type"""
        # Estimate based on payload type and content
        if isinstance(payload, PutRequest):
            return 100 + len(payload.key) + len(payload.value)  # Header + data
        elif isinstance(payload, GetRequest):
            return 100 + len(payload.key)
        # ... etc
        return 100  # Minimum message size

    def _deliver_with_bandwidth_delay(self, message: NetworkMessage, link: NetworkLink):
        """Deliver message with bandwidth-based delay"""
        # Latency = propagation delay + transmission delay
        propagation_delay = self._calculate_latency()  # Existing random latency
        transmission_delay = message.size / link.bandwidth_limit

        total_delay = propagation_delay + transmission_delay
        message.latency = total_delay

        yield self.env.timeout(total_delay)
        yield self.nodes[message.receiver_id].put(message)
```

**Configuration per Deployment:**
```python
# Local network (same AZ)
local_link = NetworkLink(
    link_id="local",
    bandwidth_limit=10_000_000_000 / 8,  # 10 Gbps
    packet_rate_limit=100_000,
    queue_depth_limit=10000
)

# Cross-AZ network
cross_az_link = NetworkLink(
    link_id="cross-az",
    bandwidth_limit=1_000_000_000 / 8,  # 1 Gbps
    packet_rate_limit=10_000,
    queue_depth_limit=1000
)

# Constrained network (for testing)
slow_link = NetworkLink(
    link_id="slow",
    bandwidth_limit=10_000_000 / 8,  # 10 Mbps
    packet_rate_limit=1_000,
    queue_depth_limit=100
)
```

**Priority:** ⭐⭐ MEDIUM-HIGH - Important for realistic distributed system behavior

---

#### 9. Resource Monitoring & Metrics
**Location:** `infra/resource_monitor.py` (new)

**Rationale:** With resource limits in place, we need observability into resource usage for debugging and capacity planning.

**Features:**
- Track resource utilization over time (CPU %, disk %, network %)
- Saturation metrics (queue depths, wait times)
- Resource exhaustion events
- Per-component resource attribution
- Time-series data for plotting

**Example API:**
```python
class ResourceMonitor:
    def __init__(self, env: simpy.Environment):
        self.env = env
        self.samples: List[ResourceSample] = []

    def sample_machine(self, machine: Machine):
        """Sample current resource usage of a machine"""
        sample = ResourceSample(
            timestamp=self.env.now,
            machine_id=machine.id,
            cpu_utilization=machine.get_cpu_utilization(),
            disk_utilization=machine.disk.used / machine.disk.capacity if machine.disk else 0,
            disk_iops_utilization=machine.disk.get_iops_utilization() if machine.disk else 0,
        )
        self.samples.append(sample)

    def get_time_series(self, metric: str, machine_id: str) -> List[Tuple[float, float]]:
        """Get time series data for a specific metric"""
        return [(s.timestamp, getattr(s, metric))
                for s in self.samples if s.machine_id == machine_id]
```

**Priority:** ⭐⭐ MEDIUM - Necessary complement to resource modeling

---

## What Should NOT Be Extracted

These are domain-specific to the KV store and should remain in the application layer:

### Keep in `models/` (Application-Specific Data Structures)
- ❌ `ShardInfo`, `RoutingTable`, `NodeInfo` - KV store sharding concepts
- ❌ `WALEntry`, `KVEntry` - Storage-specific data structures
- ❌ `ShardRoleUpdateMessage`, `NodeStatusMessage` - Control plane messages
- ✅ Move `RequestContext` to `infra/request_context.py`
- ✅ Move `NetworkMessage` to `infra/network.py` (it's general-purpose)

### Keep in `models/api.py` (KV Store API)
- ❌ All Request/Response types (Put, Get, Delete, AppendMetadata, List, Snapshot)
- ❌ `ReadConsistency` enum - application-specific concept

### Keep in `components/` (KV Store Business Logic)
- ❌ `data_node.py` - Storage and replication logic
- ❌ `gateway_node.py` - Request routing logic
- ❌ `controller.py` - Shard assignment and control plane
- ❌ `snapshot_service.py` - Snapshot coordination
- ❌ `client_library.py` - KV client SDK

**But:** Extract the common patterns (crash/recover, message listening) from these components into `BaseService`

---

## Refactoring Plan (Prioritized)

### Overview: Refactoring-First Approach

The plan is structured to **start simple** with pure refactoring (no new features), then progressively add new capabilities:

| Phase | Type | Focus | New Features? |
|-------|------|-------|---------------|
| **Phase 1** | **Refactoring** | Extract existing patterns into infra | ❌ NO - Only moves/extracts existing code |
| **Phase 2** | **Refactoring** | Update components to use extracted patterns | ❌ NO - Only applies Phase 1 refactoring |
| **Phase 3** | New Features | Enhanced observability (Tracer, utilities) | ✅ YES - Adds new tracing capabilities |
| **Phase 4** | New Features | Fault injection framework | ✅ YES - Adds centralized fault injection |
| **Phase 5** | New Features | Resource modeling (CPU, disk, network limits) | ✅ YES - Adds performance modeling |

**Critical Principle for Phases 1-2:**
- ✅ Extract duplicated code into reusable components
- ✅ Move existing models to better locations
- ✅ Consolidate identical patterns
- ❌ **NO** new functionality
- ❌ **NO** behavioral changes
- ❌ **NO** new APIs beyond what already exists

**Verification after Phases 1-2:**
- All existing tests pass without modification
- Simulation output is byte-for-byte identical
- Log format is unchanged
- Code is just better organized

---

### Phase 1: Extract Existing Patterns (Week 1) - Pure Refactoring

**Goal:** Extract common patterns from existing code into reusable infra components. **NO new features, NO behavior changes.**

**Week 1: Extraction**
1. Extract `BaseService` from existing crash/recover patterns in GatewayNode, DataNode, ClientLibrary
   - Extract common fields: `id`, `env`, `network`, `machine`, `is_crashed`, `_listen_process`
   - Extract common methods: `crash()`, `recover()`, `_listen_for_messages()`, `_on_machine_fail()`, `_on_machine_recover()`
   - Make `_handle_message()` an abstract method for subclasses
   - Location: `infra/base_service.py`

2. Extract `ContextLogger` from existing `_get_log_prefix()` methods
   - Both GatewayNode and DataNode have identical implementations
   - Just extract to a reusable class, no new functionality
   - Location: `infra/logger.py`

3. Move existing models to infra (these already exist, just moving them)
   - Move `MetricsCollector` from `models/metrics.py` to `infra/metrics.py`
   - Move `RequestContext` from `models/internal.py` to `infra/request_context.py`
   - Move `NetworkMessage` from `models/internal.py` to `infra/network.py` (already tightly coupled)
   - Update all imports

**Verification:**
- All existing tests must pass without modification
- Simulation output should be identical to before refactoring
- No new functionality added, only code organization

**Impact:**
- Eliminates code duplication
- Establishes clear infra/application boundary
- Zero behavioral changes

---

### Phase 2: Apply Refactoring to Components (Week 2) - Pure Refactoring

**Goal:** Update existing components to use the extracted base classes. **NO new features, NO behavior changes.**

**Week 2: Refactoring Components**
1. Refactor `GatewayNode` to inherit from `BaseService`
   - Remove duplicated crash/recover logic
   - Remove duplicated `_get_log_prefix()`, use `ContextLogger`
   - Implement `_handle_message()` with existing logic
   - Keep all existing behavior intact

2. Refactor `DataNode` to inherit from `BaseService`
   - Remove duplicated crash/recover logic
   - Remove duplicated `_get_log_prefix()`, use `ContextLogger`
   - Implement `_handle_message()` with existing logic
   - Keep WAL process handling as-is

3. Refactor `ClientLibrary` to use crash/recover from `BaseService` (if applicable)
   - Extract common patterns

4. Update `Controller` to use `ContextLogger` (doesn't need BaseService crash/recover)

5. Update all imports throughout the codebase
   - Fix imports for moved models (RequestContext, NetworkMessage, MetricsCollector)
   - Update all component imports

**Verification:**
- All existing tests must pass without modification
- Simulation output should be byte-for-byte identical to before
- Code coverage should remain the same or improve
- Log output format should be identical

**Impact:**
- ~60% reduction in duplicated code
- Cleaner component implementations
- Foundation for future enhancements
- Zero behavioral changes

---

### Phase 3: Enhanced Observability (Week 3) - New Features

**Goal:** Add new observability features that don't exist today.

**Week 3: Add Tracer**
1. Create `infra/tracer.py` for enhanced latency tracing (**NEW**)
   - Records timestamped events for request lifecycle
   - Calculate latencies between operations
   - Per-request trace collection

2. Add request ID generation utilities to `infra/request_context.py` (**NEW**)
   - `generate_request_id()` function using UUIDs
   - `create_request_context()` factory function

3. Integrate Tracer with Network (**NEW**)
   - Use Tracer to record detailed request timings
   - Enhance existing `request_timings` tracking

4. Add latency aggregation to `MetricsCollector` (**NEW**)
   - Percentiles (p50, p95, p99)
   - Histograms

**Impact:**
- Better end-to-end request tracing
- Latency analysis capabilities
- Foundation for performance testing

---

### Phase 4: Fault Injection Framework (Week 4) - New Features

**Goal:** Add centralized fault injection that doesn't exist today.

**Week 4: Add FaultInjector**
1. Create `infra/fault_injector.py` (**NEW**)
   - Unified API for triggering failures
   - Machine crashes with optional recovery
   - Network partitions
   - Link failures

2. Add failure scenario support (**NEW**)
   - Declarative scenario definitions
   - Time-based failure sequences
   - Coordinated failures across components

3. Enhance Network with new failure modes (**NEW**)
   - Message corruption simulation
   - Per-link delay injection
   - Jitter simulation

**Impact:**
- Easier to define complex failure scenarios
- Reproducible fault testing
- More realistic failure simulation

---

### Phase 5: Resource Modeling (Weeks 5-7) - New Features (Advanced)

This phase adds realistic resource constraints for performance testing and capacity planning:

**Week 5: CPU & Disk Capacity**
1. Create `infra/disk.py` with `DiskResource` class
2. Add `DiskResource` to `Machine`
3. Implement disk capacity limits (bytes)
4. Implement disk IOPS limits (operations/sec)
5. Implement disk throughput limits (bytes/sec)
6. Add CPU capacity management to `Machine` using SimPy Container
7. Add `consume_cpu()` method to `BaseService`

**Week 6: Network Bandwidth & Message Sizing**
1. Create `NetworkLink` abstraction in `network.py`
2. Add `size` attribute to `NetworkMessage`
3. Implement `_calculate_message_size()` for payload types
4. Add per-link bandwidth limits (bytes/sec)
5. Add per-link packet rate limits (packets/sec)
6. Implement message queuing when limits exceeded
7. Add congestion detection and metrics

**Week 7: Resource Monitoring & Integration**
1. Create `infra/resource_monitor.py`
2. Add resource utilization sampling
3. Add saturation metrics (queue depths, wait times)
4. Integrate resource limits with existing components
5. Update DataNode to use disk I/O simulation
6. Update all components to consume CPU for operations
7. Add resource usage metrics to simulation output

**Impact:**
- Realistic performance modeling under resource constraints
- Ability to test capacity planning scenarios
- Identify bottlenecks (CPU, disk, network)
- Test backpressure and load shedding mechanisms
- Validate system behavior under resource exhaustion

**Prerequisites:** Phases 1-2 complete (refactored codebase). Phases 3-4 optional but recommended.

---

## Extraction Guidelines

### For Each Component Being Extracted:

1. **Identify generic patterns** - Remove domain-specific logic
2. **Use composition over inheritance** - Where possible, use mixins or utilities instead of deep inheritance
3. **Keep interfaces simple** - Generic APIs that work for any distributed system
4. **Document thoroughly** - Infra components should be well-documented for reuse
5. **Add type hints** - Full type annotations for better IDE support
6. **Write tests** - Unit tests for all infra components

### Naming Conventions:

- **Infra modules:** `base_service.py`, `logger.py`, `tracer.py`, `fault_injector.py`
- **Infra classes:** `BaseService`, `ContextLogger`, `Tracer`, `FaultInjector`
- Avoid KV-specific names like "Shard", "Gateway", "Data" in infra layer

### Dependencies:

- Infra layer should only depend on:
  - Standard library
  - SimPy
  - Pydantic (for models)
- Infra should NOT depend on application models or components
- Application components depend on infra (one-way dependency)

---

## Quick Reference: What to Extract vs. What to Keep

### Extract to `infra/` (Generic, Reusable)

| Component | From | To | Phase | Action |
|-----------|------|-----|-------|--------|
| `BaseService` | GatewayNode, DataNode patterns | `infra/base_service.py` | 1 | Extract common crash/recover logic |
| `ContextLogger` | `_get_log_prefix()` methods | `infra/logger.py` | 1 | Extract duplicated logging |
| `RequestContext` | `models/internal.py:50-52` | `infra/request_context.py` | 1 | Move (already exists) |
| `NetworkMessage` | `models/internal.py:54-57` | `infra/network.py` | 1 | Move (already exists) |
| `MetricsCollector` | `models/metrics.py:11-30` | `infra/metrics.py` | 1 | Move (already exists) |
| `ErrorCategory` | `models/metrics.py:4-9` | `infra/metrics.py` | 1 | Move (already exists) |
| `Tracer` | N/A (new) | `infra/tracer.py` | 3 | Create new (Phase 3+) |
| `FaultInjector` | N/A (new) | `infra/fault_injector.py` | 4 | Create new (Phase 4+) |
| `DiskResource` | N/A (new) | `infra/disk.py` | 5 | Create new (Phase 5+) |
| `ResourceMonitor` | N/A (new) | `infra/resource_monitor.py` | 5 | Create new (Phase 5+) |

### Keep in Application Layer (KV-Specific)

| Component | Location | Reason |
|-----------|----------|--------|
| `ShardInfo` | `models/internal.py` | KV store sharding concept |
| `RoutingTable` | `models/internal.py` | KV store routing |
| `NodeInfo` | `models/internal.py` | Could be generic but used for KV-specific purposes |
| `WALEntry` | `models/internal.py` | Storage system specific |
| `KVEntry` | `models/internal.py` | Storage system specific |
| All API models | `models/api.py` | KV store API (Put, Get, Delete, etc.) |
| All components | `components/` | KV store business logic |

---

## Success Metrics

After extraction, we should be able to:

1. ✅ Build a new distributed system simulator (e.g., message queue, consensus algorithm) using only `infra/` components
2. ✅ Reduce code duplication by >60% in component implementations
3. ✅ Have consistent logging and metrics across all components
4. ✅ Define and execute complex fault scenarios declaratively
5. ✅ Trace any request end-to-end through the system with timestamps

---

## Example: Building a New Simulator

After extraction, creating a new Raft consensus simulator should look like:

```python
from simulator.infra.base_service import BaseService
from simulator.infra.network import Network, NetworkMessage
from simulator.infra.machine import Machine
from simulator.infra.logger import ContextLogger

class RaftNode(BaseService):
    def __init__(self, ...):
        super().__init__(...)
        self.logger = ContextLogger(self.id, self.machine, self.env)
        self.state = "follower"  # Raft-specific
        self.log = []  # Raft-specific

    def _handle_message(self, msg: NetworkMessage):
        # Raft-specific message handling
        if isinstance(msg.payload, VoteRequest):
            self.logger.info("Received vote request", msg.request_context)
            ...
```

No need to reimplement crash/recover, message listening, logging - it's all in the base class!
