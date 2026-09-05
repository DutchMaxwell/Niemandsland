"""Public developer/CI dummy; deliberately not a trained evaluator."""
BRAIN_NAME = "dummy-zero"


def score(states, side):
    return [0.0] * len(states)
