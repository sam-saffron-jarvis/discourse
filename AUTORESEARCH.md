# DO NOT MERGE — autoresearch experiment branch

Long-lived target of an automated optimisation loop
(`autoresearch/run.sh`) trying to reduce CI runtime of the system test
suite. Each iteration is rebased onto `8d43a7c5d7c2695c482ea75230eb3638b82cdf1e` and replays every
prior iteration's commit (and any subsequent revert) on top, so the
branch's `git log` is a chronological record of what the model has
tried.

Rebase base: `8d43a7c5d7c2695c482ea75230eb3638b82cdf1e`
