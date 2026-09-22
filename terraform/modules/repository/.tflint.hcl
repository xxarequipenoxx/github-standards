# tflint reads the config of each directory in --recursive mode; keep this file identical
# to terraform/.tflint.hcl.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
