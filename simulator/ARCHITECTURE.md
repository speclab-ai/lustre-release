# Simulator Architecture Guide

## Overview

This document defines the architecture of the distributed systems simulator, clarifying the separation between the reusable infrastructure layer and application-specific components.

## Layer Separation

```
┌─────────────────────────────────────────────┐
│          Application Layer                  │
│  (KV Store specific: components/, models/)  │
│                                             │
│  - Business logic (sharding, replication)   │
│  - API definitions (Put, Get, Delete)       │
│  - Domain models (ShardInfo, WALEntry)      │
└─────────────────────────────────────────────┘
                    ▲
                    │ depends on
                    │
┌─────────────────────────────────────────────┐
│        Infrastructure Layer (infra/)        │
│                                             │
│  - Generic distributed system primitives    │
│  - Message passing, failures, observability │
│  - Reusable across any distributed system   │
└─────────────────────────────────────────────┘
                    ▲
                    │ depends on
                    │
┌─────────────────────────────────────────────┐
│          Foundation Libraries               │
│     (SimPy, Pydantic, Python stdlib)        │
└─────────────────────────────────────────────┘
```

## Directory Structure

```
simulator/
├── infra/                      # Reusable infrastructure (generic)
│   ├── __init__.py
│   ├── base_service.py        # [Phase 1] Base class for services
│   ├── machine.py             # [✓] Machine abstraction (+ CPU in Phase 4)
│   ├── network.py             # [✓] Message passing (+ bandwidth/IOPS in Phase 4)
│   ├── availability_zone.py   # [✓] Fault domain abstraction
│   ├── load_balancer.py       # [✓] Basic load balancing
│   ├── logger.py              # [Phase 1] Contextual logging utilities
│   ├── request_context.py     # [Phase 2] Request tracking utilities
│   ├── metrics.py             # [Phase 2] Metrics & tracing (move from models/)
│   ├── fault_injector.py      # [Phase 3] Centralized fault injection
│   ├── disk.py                # [Phase 4] Disk resource modeling
│   └── resource_monitor.py    # [Phase 4] Resource utilization monitoring
│
├── models/                     # Application-specific data structures
│   ├── __init__.py
│   ├── base.py                # Base Request/Response (keep)
│   ├── api.py                 # KV API: Put, Get, Delete, etc. (keep)
│   ├── internal.py            # KV internals: ShardInfo, WALEntry, etc. (keep)
│   └── metrics.py             # [MOVE to infra/metrics.py in Phase 2]
│
├── components/                 # KV store business logic
│   ├── __init__.py
│   ├── data_node.py           # Storage & replication (refactor in Phases 1 & 4)
│   ├── gateway_node.py        # Request routing (refactor in Phase 1)
│   ├── controller.py          # Shard management (refactor in Phase 1)
│   ├── snapshot_service.py    # Snapshot coordination (keep)
│   └── client_library.py      # Client SDK (refactor in Phase 1)
│
└── simulation.py               # Main orchestrator
```

## Component Classification

### Infrastructure Layer (`infra/`)

**Purpose:** Generic, reusable primitives for building distributed system simulators

**Characteristics:**
- ✅ No domain-specific logic (no sharding, KV store, etc.)
- ✅ Can be used to build simulators for other systems (Raft, Kafka, etc.)
- ✅ Depends only on: SimPy, Pydantic, Python stdlib
- ✅ Well-documented with examples
- ✅ Fully type-annotated

**Components:**

| Component | Status | Phase | Description |
|-----------|--------|-------|-------------|
| `machine.py` | ✅ Done | Base | Machine abstraction with fail/recover, clock skew |
| `network.py` | ✅ Done | Base | Message delivery with latency, drops, partitions |
| `availability_zone.py` | ✅ Done | Base | Fault domain grouping with cascading failures |
| `load_balancer.py` | ✅ Done | Base | Simple round-robin/random load balancing |
| `base_service.py` | 🔨 Phase 1 | Refactoring | Extract crash/recover pattern from existing code |
| `logger.py` | 🔨 Phase 1 | Refactoring | Extract _get_log_prefix() from existing code |
| `request_context.py` | 🔨 Phase 1 | Refactoring | Move RequestContext from models/ (already exists) |
| `metrics.py` | 🔨 Phase 1 | Refactoring | Move MetricsCollector from models/ (already exists) |
| `tracer.py` | 🔨 Phase 3 | New Feature | Enhanced latency tracing (NEW) |
| `fault_injector.py` | 🔨 Phase 4 | New Feature | Centralized fault injection framework (NEW) |
| `disk.py` | 🔨 Phase 5 | New Feature | Disk with capacity, throughput, IOPS limits (NEW) |
| `resource_monitor.py` | 🔨 Phase 5 | New Feature | Resource utilization tracking and metrics (NEW) |

**Phase 5 Enhancements to Existing Components:**
- `machine.py` → Add CPU capacity management (SimPy Container)
- `network.py` → Add NetworkLink, bandwidth/IOPS limits, message sizing, congestion handling

### Important: Phases 1-2 = Pure Refactoring (No New Features)

The first two phases are **strictly refactoring only**:
- Phase 1: Extract existing patterns into infra (BaseService, ContextLogger, move existing models)
- Phase 2: Refactor components to use extracted patterns
- **Goal:** Zero behavioral changes, just better code organization
- **Verification:** All tests pass unchanged, simulation output identical

Phases 3+ add new features on top of the refactored foundation.

---

### Application Layer (`components/`, `models/`)

**Purpose:** KV store-specific business logic and data structures

**Characteristics:**
- ❌ Domain-specific (sharding, replication, WAL, etc.)
- ❌ Depends on infra layer
- ✅ Implements specific distributed system (KV store)

**Components:**

| Component | Type | Keep/Refactor | Description |
|-----------|------|---------------|-------------|
| `models/api.py` | Domain Model | Keep | KV API: Put, Get, Delete, List, Snapshot |
| `models/internal.py` | Domain Model | Partially refactor | Keep ShardInfo, WALEntry; move RequestContext to infra |
| `models/base.py` | Domain Model | Keep | Base Request/Response classes |
| `components/data_node.py` | Service | Refactor | Extract common patterns to BaseService |
| `components/gateway_node.py` | Service | Refactor | Extract common patterns to BaseService |
| `components/controller.py` | Service | Refactor | Extract common patterns to BaseService |
| `components/snapshot_service.py` | Service | Keep | Snapshot-specific logic |
| `components/client_library.py` | Client | Refactor | Extract crash/recover pattern |

---

## Design Patterns

### 1. Base Service Pattern

All services should inherit from `BaseService` which provides:

```python
# In infra/base_service.py
class BaseService(BaseModel):
    """Base class for all simulation services"""
    id: str
    env: simpy.Environment
    network: Network
    machine: Machine
    is_crashed: bool = False
    _listen_process: Optional[simpy.Process] = None

    def __init__(self, ...):
        super().__init__(...)
        self.machine.register_callbacks(self._on_machine_fail, self._on_machine_recover)
        self._listen_process = self.env.process(self._listen_for_messages())

    def crash(self):
        """Crash this service"""
        ...

    def recover(self):
        """Recover this service"""
        ...

    def _listen_for_messages(self):
        """Base message listening loop"""
        while True:
            if self.is_crashed:
                yield self.env.timeout(1)
                continue
            msg = yield self.network.get_inbox(self.id).get()
            self._handle_message(msg)

    @abstractmethod
    def _handle_message(self, msg: NetworkMessage):
        """Handle a received message - implemented by subclass"""
        raise NotImplementedError()

    def _on_machine_fail(self, machine_id: str):
        """Called when underlying machine fails"""
        self.crash()

    def _on_machine_recover(self, machine_id: str):
        """Called when underlying machine recovers"""
        self.recover()
```

**Usage in application layer:**

```python
# In components/data_node.py
class DataNode(BaseService):
    # KV-specific fields
    kv_store: Dict[str, KVEntry] = {}
    wal: List[WALEntry] = []
    is_leader_for_shards: List[str] = []

    def _handle_message(self, msg: NetworkMessage):
        # KV-specific message handling
        if isinstance(msg.payload, PutRequest):
            self._handle_put(msg)
        elif isinstance(msg.payload, GetRequest):
            self._handle_get(msg)
        ...
```

### 2. Contextual Logging Pattern

Use `ContextLogger` instead of direct Python logging:

```python
# In infra/logger.py
class ContextLogger:
    def __init__(self, component_id: str, machine: Machine, env: simpy.Environment):
        ...

    def info(self, msg: str, request_context: Optional[RequestContext] = None):
        prefix = self._get_prefix(request_context)
        logger.info(f"{prefix} {msg}")

    def error(self, msg: str, request_context: Optional[RequestContext] = None):
        prefix = self._get_prefix(request_context)
        logger.error(f"{prefix} {msg}")
```

**Usage:**

```python
class DataNode(BaseService):
    def __init__(self, ...):
        super().__init__(...)
        self.logger = ContextLogger(self.id, self.machine, self.env)

    def _handle_put(self, msg: NetworkMessage):
        self.logger.info("Processing PUT request", msg.request_context)
        # ... business logic
```

### 3. Request Context Pattern

Generate and propagate request context consistently:

```python
# In infra/request_context.py
def create_request_context() -> RequestContext:
    return RequestContext(request_id=str(uuid.uuid4()))

# In application code
context = create_request_context()
request = PutRequest(request_id=context.request_id, key="foo", value="bar")
msg = NetworkMessage(
    sender_id=self.id,
    receiver_id=target_id,
    payload=request,
    request_context=context,
    timestamp=self.env.now
)
self.network.send_message(msg)
```

### 4. Fault Injection Pattern

Use `FaultInjector` for controlled failure scenarios:

```python
# In test or simulation setup
fault_injector = FaultInjector(env, network)
fault_injector.register_machine("data-node-1", machine1)
fault_injector.register_az("us-west-1", az1)

# Inject failures
env.process(fault_injector.crash_machine("data-node-1", duration=10.0))
env.process(fault_injector.partition_network("us-west-1", "us-east-1", duration=30.0))

# Or run a scenario
scenario = FailureScenario([
    (5.0, "crash_machine", {"machine_id": "data-node-1"}),
    (15.0, "recover_machine", {"machine_id": "data-node-1"}),
    (20.0, "partition_az", {"az1": "us-west-1", "az2": "us-east-1"}),
])
env.process(fault_injector.run_scenario(scenario))
```

---

## Dependency Rules

### ✅ Allowed Dependencies

```
Application Components → Infra Layer → SimPy/Pydantic
Application Models → Pydantic
Infra → SimPy/Pydantic (NO application imports)
```

### ❌ Forbidden Dependencies

```
Infra → Application Components (NEVER)
Infra → Application Models (NEVER, except generic base types)
```

### Example Violations to Avoid

```python
# ❌ BAD: Infra importing from application models
# In infra/network.py
from simulator.models.internal import ShardInfo  # WRONG!

# ✅ GOOD: Keep infra generic
# In infra/network.py
from typing import Any  # Generic payload type
```

---

## Migration Checklist

When refactoring an application component to use infra:

- [ ] Identify common patterns (crash/recover, logging, etc.)
- [ ] Replace direct logging with `ContextLogger`
- [ ] Inherit from `BaseService` if applicable
- [ ] Move `_handle_message` logic to application-specific method
- [ ] Remove duplicated `_get_log_prefix`, `crash()`, `recover()` methods
- [ ] Use `create_request_context()` for request ID generation
- [ ] Ensure no infra components import application models
- [ ] Add type hints to all new/modified code
- [ ] Update tests to reflect new structure

---

## Testing Strategy

### Infra Layer Testing

Each infra component should have:

1. **Unit tests** - Test in isolation with mocks
2. **Integration tests** - Test with real SimPy environment
3. **Example usage** - Demonstrate how to use the component

Example:

```python
# tests/infra/test_base_service.py
def test_base_service_crash_recovery():
    env = simpy.Environment()
    network = Network(env)
    machine = Machine(id="m1", az="az1")

    class TestService(BaseService):
        def _handle_message(self, msg): pass

    service = TestService(id="s1", env=env, network=network, machine=machine)

    assert not service.is_crashed
    service.crash()
    assert service.is_crashed
    service.recover()
    assert not service.is_crashed
```

### Application Layer Testing

Components should be tested with real infra:

```python
# tests/components/test_data_node.py
def test_data_node_handles_put():
    env = simpy.Environment()
    network = Network(env)
    machine = Machine(id="m1", az="az1")

    data_node = DataNode(id="dn1", env=env, network=network, machine=machine, ...)

    # Send PUT request
    put_req = PutRequest(request_id="req1", key="foo", value="bar")
    msg = NetworkMessage(sender_id="client", receiver_id="dn1", payload=put_req, ...)
    network.send_message(msg)

    env.run(until=1.0)

    assert "foo" in data_node.kv_store
```

---

## Resource Modeling Use Cases (Phase 4)

Resource modeling (CPU, disk, network bandwidth/IOPS) enables advanced simulation scenarios that go beyond correctness testing to include performance and capacity planning.

### Why Resource Modeling Matters

Without resource constraints, simulations only test **correctness** (does the system produce the right results?). With resource modeling, you can test:

1. **Performance under load** - How does latency degrade as load increases?
2. **Capacity planning** - What happens when you hit CPU/disk/network limits?
3. **Bottleneck identification** - Which resource becomes the bottleneck first?
4. **Backpressure behavior** - Does the system gracefully handle resource exhaustion?
5. **Resource contention** - How do components compete for shared resources?

### Simulation Scenarios Enabled by Resource Modeling

#### Scenario 1: CPU Saturation
```python
# Simulate a data node under heavy write load
machine = Machine(
    id="dn1",
    az="us-west-1",
    cpu_capacity=100.0  # Limited CPU
)

# Generate high request rate
for i in range(1000):
    env.process(send_put_request(f"key-{i}", f"value-{i}"))

# Observe:
# - Request latency increases as CPU saturates
# - Queue depth grows
# - Some requests may timeout
# - CPU utilization approaches 100%
```

**Questions this answers:**
- At what request rate does the system become CPU-bound?
- How does latency increase as CPU utilization grows?
- Does the system implement backpressure or just queue indefinitely?

#### Scenario 2: Disk Full
```python
# Simulate running out of disk space
machine = Machine(
    id="dn1",
    az="us-west-1",
    disk=DiskResource(
        capacity=1_000_000,  # Only 1MB of disk
        throughput_limit=10_000_000,  # 10 MB/s
        write_iops_limit=1000
    )
)

# Write until disk full
for i in range(10000):
    env.process(send_put_request(f"key-{i}", "x" * 1000))  # 1KB values

# Observe:
# - Writes succeed until disk full
# - After disk full, writes fail with appropriate error
# - System should gracefully reject writes, not crash
# - Metrics should show disk utilization approaching 100%
```

**Questions this answers:**
- How does the system handle disk exhaustion?
- Are old entries evicted or do writes fail?
- Do clients receive appropriate error messages?
- Does the system recover when disk space is freed?

#### Scenario 3: Network Bandwidth Saturation
```python
# Simulate cross-AZ replication with limited bandwidth
network = Network(env)

# Cross-AZ link has limited bandwidth
cross_az_link = NetworkLink(
    link_id="us-west-1 -> us-east-1",
    bandwidth_limit=10_000_000,  # Only 10 MB/s
    packet_rate_limit=10_000,
    queue_depth_limit=1000
)
network.register_link(cross_az_link, "us-west-1", "us-east-1")

# Replicate large objects across AZs
for i in range(100):
    data = "x" * 1_000_000  # 1MB values
    env.process(replicate_to_remote_az(f"key-{i}", data))

# Observe:
# - Replication latency increases as bandwidth saturates
# - Message queue grows
# - May see dropped messages if queue full
# - Bandwidth utilization approaches 100%
```

**Questions this answers:**
- Is cross-AZ bandwidth the bottleneck for replication?
- How long does replication lag when bandwidth is limited?
- Should we implement compression to reduce bandwidth usage?
- What happens when the replication queue overflows?

#### Scenario 4: Disk IOPS Limit (Small Writes)
```python
# Simulate high-frequency small writes (common in WAL)
machine = Machine(
    id="dn1",
    az="us-west-1",
    disk=DiskResource(
        capacity=1_000_000_000,  # 1GB (plenty of space)
        throughput_limit=100_000_000,  # 100 MB/s (plenty of throughput)
        write_iops_limit=100  # Only 100 writes/sec (realistic for HDD)
    )
)

# High frequency small writes
for i in range(10000):
    env.process(send_put_request(f"key-{i}", "small"))  # Small values

# Observe:
# - Disk has plenty of capacity and throughput
# - But IOPS limit causes backlog
# - Write latency increases due to IOPS queueing
# - System is IOPS-bound, not bandwidth-bound
```

**Questions this answers:**
- Are we IOPS-bound or bandwidth-bound?
- Should we batch small writes to reduce IOPS?
- Would switching from HDD to SSD (higher IOPS) help?
- How does write batching affect latency?

#### Scenario 5: Multi-Resource Contention
```python
# Simulate simultaneous CPU, disk, and network pressure
machine = Machine(
    id="dn1",
    az="us-west-1",
    cpu_capacity=100.0,
    disk=DiskResource(
        capacity=1_000_000_000,
        throughput_limit=50_000_000,  # 50 MB/s
        write_iops_limit=500
    )
)

# Mix of workloads:
# - Large writes (disk throughput bound)
# - Small writes (IOPS bound)
# - Complex queries (CPU bound)
# - Cross-AZ replication (network bound)

for i in range(1000):
    if i % 4 == 0:
        env.process(large_write(...))  # Disk throughput
    elif i % 4 == 1:
        env.process(small_write(...))  # Disk IOPS
    elif i % 4 == 2:
        env.process(complex_query(...))  # CPU
    else:
        env.process(replicate(...))  # Network

# Observe:
# - Which resource becomes the bottleneck?
# - How do different workloads compete for resources?
# - Should we prioritize certain operations?
```

**Questions this answers:**
- Which resource is the primary bottleneck in production?
- How should we allocate resources across different workload types?
- Would adding more CPU/disk/network help, or is one resource the clear bottleneck?

### Performance Metrics from Resource Modeling

With resource modeling, you can collect:

1. **Utilization Metrics**
   - CPU utilization % over time
   - Disk space utilization %
   - Disk IOPS utilization %
   - Network bandwidth utilization %

2. **Saturation Metrics**
   - CPU queue depth
   - Disk I/O queue depth
   - Network message queue depth
   - Time spent waiting for resources

3. **Latency Breakdown**
   - Processing time (CPU)
   - Disk I/O time
   - Network transmission time
   - Queueing time

4. **Capacity Planning**
   - Maximum sustainable request rate
   - Time until resource exhaustion
   - Resource headroom at various load levels

### Integration with Fault Injection

Resource modeling + fault injection = powerful testing:

```python
# Scenario: Network partition + resource pressure
fault_injector = FaultInjector(env, network)

# Start with resource-constrained setup
machine = Machine(id="dn1", cpu_capacity=50.0)  # Half normal CPU

# Apply load
env.process(generate_load(rate=100))  # requests/sec

# Inject failure at 30 seconds
env.process(fault_injector.crash_machine("dn2", at_time=30.0, duration=60.0))

# Questions:
# - Can dn1 handle the extra load when dn2 is down?
# - Does dn1's limited CPU cause cascade failures?
# - How long until dn1 becomes saturated?
```

---

## Future Considerations

### Potential Additional Infra Components

Beyond Phase 4, future enhancements could include:

1. **Consensus Abstraction** - Generic Raft/Paxos primitives that can be reused
2. **State Machine Replication** - Generic RSM framework for building replicated services
3. **Message Serialization** - Advanced size calculation for bandwidth modeling (beyond basic estimation)
4. **Clock Synchronization** - NTP simulation, drift modeling, vector clocks
5. **Data Corruption Simulation** - Bit flips, partial writes, silent corruption
6. **Memory Limits** - RAM constraints, OOM behavior, swap simulation
7. **Process Isolation** - Multi-process per machine, resource isolation between processes

### Making Infra a Standalone Package

Eventually, we may want to:

1. Extract `infra/` into a separate Python package
2. Publish to PyPI as `simpy-distributed` or similar
3. Create documentation site
4. Add CLI for generating new simulator projects

```bash
# Future vision
pip install simpy-distributed

# Generate new simulator
simpy-distributed init --name my-raft-simulator
cd my-raft-simulator
# Start implementing Raft-specific logic using infra base classes
```

---

## Questions & Decisions

### Open Questions

1. **Should `NetworkMessage` move to `infra/network.py`?**
   - **Decision:** YES - It's generic enough for any message-passing system

2. **Should `RequestContext` move to `infra/request_context.py`?**
   - **Decision:** YES - Request tracing is a common pattern across distributed systems

3. **Should `LoadBalancer` stay in infra or be application-specific?**
   - **Decision:** KEEP in infra - It's a generic routing abstraction

4. **How to handle domain-specific error categories in `MetricsCollector`?**
   - **Decision:** Make `ErrorCategory` extensible or use string-based categories

### Resolved Decisions

- ✅ Use Pydantic BaseModel for all infra components (consistency with existing code)
- ✅ Use composition over deep inheritance (BaseService is shallow, specific logic in subclasses)
- ✅ Keep logging synchronous (no async complications in SimPy)
- ✅ Use Python 3.9+ type hints throughout

---

## Resources

- [SimPy Documentation](https://simpy.readthedocs.io/)
- [Pydantic Documentation](https://docs.pydantic.dev/)
- [TODO.md](./TODO.md) - Detailed refactoring tasks
- [simulation.py](./simulation.py) - Main orchestrator showing how components fit together
