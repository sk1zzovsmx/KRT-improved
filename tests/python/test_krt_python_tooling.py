import importlib
import importlib.util
import unittest
from pathlib import Path


def load_krt_module():
    repo_root = Path(__file__).resolve().parents[2]
    krt_path = repo_root / "tools" / "krt.py"
    spec = importlib.util.spec_from_file_location("krt_module", krt_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _module_available(module_name: str) -> bool:
    return importlib.util.find_spec(module_name) is not None


class PythonToolingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.krt = load_krt_module()
        self.orig_run_command = self.krt.run_command

    def tearDown(self) -> None:
        self.krt.run_command = self.orig_run_command

    def test_python_quality_check_runs_expected_steps_in_order(self) -> None:
        called = []

        def fake_run_command(cmd):
            called.append(cmd)
            return 0

        self.krt.run_command = fake_run_command
        args = self.krt.argparse.Namespace(
            targets=["tools", "tests/python"],
            skip_ruff=False,
            skip_pytest=False,
        )
        exit_code = self.krt.python_quality_check(args)

        expected_prefix = [
            [
                self.krt.sys.executable,
                "-m",
                "ruff",
                "check",
                "tools",
                "tests/python",
            ],
            [
                self.krt.sys.executable,
                "-m",
                "ruff",
                "format",
                "--check",
                "tools",
                "tests/python",
            ],
            [self.krt.sys.executable, "-m", "pytest", "tests/python"],
        ]
        self.assertEqual(exit_code, 0)
        self.assertEqual(called, expected_prefix)

    def test_python_quality_check_stops_on_first_nonzero(self) -> None:
        called = []

        def fake_run_command(cmd):
            called.append(cmd)
            return 7 if len(called) == 1 else 0

        self.krt.run_command = fake_run_command
        args = self.krt.argparse.Namespace(
            targets=["tools"],
            skip_ruff=False,
            skip_pytest=False,
        )
        exit_code = self.krt.python_quality_check(args)

        self.assertEqual(exit_code, 7)
        self.assertEqual(len(called), 1)
        self.assertEqual(
            called[0],
            [self.krt.sys.executable, "-m", "ruff", "check", "tools"],
        )

    def test_dev_requirements_has_expected_entries(self) -> None:
        requirements_path = Path(__file__).resolve().parents[2] / "tools" / "requirements-dev.txt"
        text = requirements_path.read_text(encoding="utf-8")
        self.assertIn("ruff", text)
        self.assertIn("pytest", text)
        self.assertIn("jsonschema", text)
        self.assertIn("Pillow", text)


@unittest.skipUnless(_module_available("jsonschema"), "jsonschema is not installed in this environment.")
class JsonSchemaSmokeTest(unittest.TestCase):
    def test_jsonschema_basic_import_and_parse(self) -> None:
        import jsonschema

        jsonschema.validate({"a": 1}, {"type": "object"})


@unittest.skipUnless(_module_available("PIL"), "Pillow is not installed in this environment.")
class PillowSmokeTest(unittest.TestCase):
    def test_pillow_basic_image_roundtrip(self) -> None:
        from PIL import Image

        image = Image.new("RGB", (2, 2), (1, 2, 3))
        self.assertEqual(image.size, (2, 2))


if __name__ == "__main__":
    unittest.main()
