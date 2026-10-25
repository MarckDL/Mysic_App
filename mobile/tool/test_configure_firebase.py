import unittest

from configure_firebase import build_config


class ClientConfigTest(unittest.TestCase):
    def fixture(self):
        return {
            "project_info": {"project_id": "test-project", "project_number": "123"},
            "client": [{
                "client_info": {"mobilesdk_app_id": "test-app", "android_client_info": {"package_name": "com.mysic.mysic"}},
                "api_key": [{"current_key": "client-configuration-test"}],
                "oauth_client": [{"client_type": 3, "client_id": "test-web-client"}],
            }],
        }

    def test_extracts_client_configuration(self):
        self.assertEqual(build_config(self.fixture())["GOOGLE_SERVER_CLIENT_ID"], "test-web-client")

    def test_rejects_admin_credentials(self):
        with self.assertRaises(ValueError):
            build_config({"type": "service_account"})

    def test_rejects_wrong_android_package(self):
        data = self.fixture()
        data["client"][0]["client_info"]["android_client_info"]["package_name"] = "other.app"
        with self.assertRaises(ValueError):
            build_config(data)

    def test_rejects_missing_web_client(self):
        data = self.fixture()
        data["client"][0]["oauth_client"] = []
        with self.assertRaises(ValueError):
            build_config(data)


if __name__ == "__main__":
    unittest.main()
