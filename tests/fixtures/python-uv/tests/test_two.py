from fixture_python import database_url, two


def test_two() -> None:
    assert two() == 2


def test_database_backend_is_reported() -> None:
    url = database_url()
    assert url is None or url.startswith("postgresql://")
