mock_provider "null" {}

run "records_the_name" {
  command = plan

  variables {
    name = "fixture-under-test"
  }

  assert {
    condition     = output.name == "fixture-under-test"
    error_message = "the output must echo the name variable"
  }
}

run "rejects_uppercase_names" {
  command = plan

  variables {
    name = "Fixture"
  }

  expect_failures = [var.name]
}
