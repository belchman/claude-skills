# Reference

## Dependency categories

When assessing a candidate for deepening, classify its dependencies:

### 1. In-process

Pure computation, in-memory state, no I/O. Always deepenable — merge the modules and test directly.

### 2. Local-substitutable

Has a local test stand-in (e.g. PGLite for Postgres, in-memory FS). Deepenable if the substitute exists. Tested with the stand-in running in the suite.

### 3. Remote but owned (Ports & Adapters)

Your own services across a network boundary (microservices, internal APIs). Define a port at the module boundary. The deep module owns the logic; the transport is injected. Tests use an in-memory adapter; production uses HTTP/gRPC/queue.

Recommendation shape: "Define a shared interface (port), implement an HTTP adapter for production and an in-memory adapter for testing, so the logic can be tested as one deep module even though it's deployed across a network boundary."

### 4. True external (Mock)

Third-party services (Stripe, Twilio, etc.) you don't control. Mock at the boundary. The deep module takes the dependency as an injected port; tests provide a mock.

## Testing strategy

Core principle: **replace, don't layer.**

- Old unit tests on shallow modules are waste once boundary tests exist — delete them
- Write new tests at the deepened module's interface boundary
- Assert on observable outcomes through the public interface, not internal state
- Tests should survive internal refactors

## Issue template

<issue-template>

## Problem

Architectural friction:

- Which modules are shallow and tightly coupled
- What integration risk lives in the seams
- Why this hurts navigation/maintenance

## Proposed Interface

The chosen design:

- Interface signature (types, methods, params)
- Usage example
- What complexity it hides

## Dependency Strategy

Which category applies and how deps are handled:

- **In-process**: merged directly
- **Local-substitutable**: tested with [stand-in]
- **Ports & adapters**: port, production adapter, test adapter
- **Mock**: mock boundary for external services

## Testing Strategy

- **New boundary tests**: behaviors to verify at the interface
- **Old tests to delete**: shallow-module tests that become redundant
- **Test environment**: any local stand-ins or adapters required

## Implementation Recommendations

Durable architectural guidance NOT coupled to current file paths:

- What the module should own (responsibilities)
- What it should hide (implementation details)
- What it should expose (interface contract)
- How callers should migrate

</issue-template>
