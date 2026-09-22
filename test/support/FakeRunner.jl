# =============================================================================
# Test doubles for the SSH_utils.Runner interface. No tests here.
# =============================================================================

# Implements neither `capture` nor `execute`, to check that the interface
# fails loudly instead of falling back to the shell.
struct IncompleteRunner <: SSH_utils.Runner.AbstractRunner end
