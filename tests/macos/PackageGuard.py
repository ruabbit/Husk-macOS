# SPDX-License-Identifier: GPL-2.0-or-later
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts'))
spec = importlib.util.spec_from_file_location('package_macos', ROOT / 'scripts/package_macos.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackageGuard(unittest.TestCase):
    def test_running_main_and_helpers_preserve_candidate(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / 'Husk Mac.app'
            app.mkdir()
            sentinel = app / 'existing-candidate'
            sentinel.write_text('preserve')
            for executable in ('Contents/MacOS/HuskMac', 'Contents/Helpers/NativeRunner.app/Contents/MacOS/NativeRunner',
                               'Contents/Helpers/VMRunner.app/Contents/MacOS/VMRunner'):
                with self.subTest(executable=executable), patch.object(packager.subprocess, 'check_output',
                        return_value=f'1234 {app / executable}\n'):
                    with self.assertRaisesRegex(RuntimeError, 'quit it normally'):
                        packager.package(Path(temp) / 'absent-source', None, None, None, app)
                    self.assertEqual(sentinel.read_text(), 'preserve')

    def test_other_bundles_are_not_blockers(self):
        with patch.object(packager.subprocess, 'check_output', return_value='9 /tmp/HuskMac.app-other/Contents/MacOS/HuskMac\n'):
            packager.assert_bundle_idle(Path('/tmp/HuskMac.app'))

    def test_unreadable_process_list_fails_closed(self):
        with patch.object(packager.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(1, 'ps')):
            with self.assertRaises(subprocess.CalledProcessError):
                packager.assert_bundle_idle(Path('/tmp/HuskMac.app'))


if __name__ == '__main__':
    unittest.main()
