"""Convierte la configuración CLIENTE Android a --dart-define-from-file.

No acepta ni procesa cuentas de servicio administrativas. Ejecutar desde mobile/:
python3 tool/configure_firebase.py /ruta/google-services.json
"""
import argparse
import json
from pathlib import Path


def build_config(data):
    if "private_key" in data or data.get("type") == "service_account":
        raise ValueError("Se requiere google-services.json del cliente, no una cuenta administrativa")
    clients = [client for client in data.get("client", [])
               if client.get("client_info", {}).get("android_client_info", {}).get("package_name") == "com.mysic.mysic"]
    if len(clients) != 1:
        raise ValueError("Debe existir una app Android con paquete com.mysic.mysic")
    client = clients[0]
    oauth_clients = client.get("oauth_client", []) + client.get("services", {}).get("appinvite_service", {}).get("other_platform_oauth_client", [])
    web_ids = {item.get("client_id") for item in oauth_clients if item.get("client_type") == 3 and item.get("client_id")}
    if len(web_ids) != 1:
        raise ValueError("No se encontró un único cliente OAuth web; habilita Google y descarga nuevamente el JSON")
    config = {
        "FIREBASE_API_KEY": client.get("api_key", [{}])[0].get("current_key", "") if client.get("api_key") else "",
        "FIREBASE_APP_ID": client.get("client_info", {}).get("mobilesdk_app_id", ""),
        "FIREBASE_MESSAGING_SENDER_ID": str(data.get("project_info", {}).get("project_number", "")),
        "FIREBASE_PROJECT_ID": data.get("project_info", {}).get("project_id", ""),
        "GOOGLE_SERVER_CLIENT_ID": next(iter(web_ids)),
        "API_BASE_URL": "http://10.0.2.2:3000",
    }
    if not all(isinstance(value, str) and value.strip() for value in config.values()):
        raise ValueError("La configuración cliente está incompleta")
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("google_services", type=Path)
    parser.add_argument("--output", type=Path, default=Path("config/firebase.android.json"))
    args = parser.parse_args()
    try:
        config = build_config(json.loads(args.google_services.read_text()))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x") as output:
            json.dump(config, output, indent=2)
            output.write("\n")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"No se generó configuración: {error}\n")
    print(f"Configuración cliente generada en {args.output}. No incluirla en Git.")


if __name__ == "__main__":
    main()
