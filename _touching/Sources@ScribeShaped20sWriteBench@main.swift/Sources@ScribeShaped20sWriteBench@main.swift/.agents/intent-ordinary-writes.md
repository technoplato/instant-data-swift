The accelerated mode must use ordinary local materialize + durable outbox writes. It must not wait for server acceptance on each revision; server convergence is observed separately after the burst.
