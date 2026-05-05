# When to Mock

Mock at **system boundaries** only:

- External APIs (payment, email, etc.)
- Databases (sometimes — prefer a test DB)
- Time/randomness
- Filesystem (sometimes)

Don't mock your own classes/modules, internal collaborators, or anything you control.

## Designing for mockability

**1. Use dependency injection** — pass external deps in instead of creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**2. Prefer SDK-style interfaces over generic fetchers** — specific functions per operation, not one generic with conditional logic:

```typescript
// GOOD: each function is independently mockable
const api = {
  getUser: (id) => fetch(`/users/${id}`),
  getOrders: (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data) => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: mocking requires conditional logic in the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach: each mock returns one shape; no conditionals in test setup; clearer which endpoints a test exercises; type safety per endpoint.
