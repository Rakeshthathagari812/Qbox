"""Only the model code that was checked may run."""

import json

import pytest

from ai_server import models
from ai_server.config import DEV_KEY, Settings, check_settings


@pytest.fixture
def model(tmp_path, monkeypatch):
    path = tmp_path / "some-model"
    path.mkdir()
    (path / "code.py").write_bytes(b"x = 1\n")
    (path / "weights.safetensors").write_bytes(b"123")
    kept = tmp_path / "kept.json"
    fingerprint = __import__("hashlib").sha256(b"x = 1\n").hexdigest()
    kept.write_text(json.dumps({"some-model": {"code.py": fingerprint}}))
    monkeypatch.setattr(models, "_CODE", kept)
    return path


def test_the_checked_code_is_accepted(model):
    models.check_code(model)


def test_changed_added_missing_or_pickled_is_refused(model):
    (model / "code.py").write_bytes(b"x = 2\n")
    with pytest.raises(models.ModelChanged, match="not the checked version"):
        models.check_code(model)
    (model / "code.py").write_bytes(b"x = 1\n")
    (model / "more.py").write_bytes(b"")
    with pytest.raises(models.ModelChanged, match="unexpected code"):
        models.check_code(model)
    (model / "more.py").unlink()
    (model / "pytorch_model.bin").write_bytes(b"")
    with pytest.raises(models.ModelChanged, match="unexpected files"):
        models.check_code(model)
    (model / "pytorch_model.bin").unlink()
    (model / "code.py").unlink()
    with pytest.raises(models.ModelChanged):
        models.check_code(model)


def test_every_model_has_fingerprints():
    kept = json.loads((models.Path(models.__file__).with_name("model_code.json")).read_text(encoding="utf-8"))
    for repo, _ in models.REPOS.values():
        assert kept[repo.split("/")[1]], repo


def test_production_needs_a_private_key():
    with pytest.raises(ValueError, match="QBOX_AI_KEY"):
        check_settings(Settings(app_env="production", key=DEV_KEY))
    check_settings(Settings(app_env="production", key="k" * 40))
