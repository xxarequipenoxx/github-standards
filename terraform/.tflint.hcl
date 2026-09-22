# Bundled terraform ruleset only (no plugin download). modules/repository carries the same
# file because tflint --recursive reads the config of each directory it inspects.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
