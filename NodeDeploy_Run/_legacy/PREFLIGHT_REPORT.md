# NodeDeploy Preflight Report

- **Fecha**: 2026-05-26 13:57:42
- **Source**: `C:\Users\user\Desktop\1.Node_Preparation`
- **Workdir**: `C:\Users\user\Desktop\NodeDeploy_Run`
- **Maquina**: VM-WIN11 / user

## Resumen

- OK   : 20
- WARN : 4
- FAIL : 0

## Findings

| Level | Area | Detalle |
|-------|------|---------|
| OK | Admin | Sesion elevada |
| INFO | OS | Microsoft Windows 11 Pro 10.0.26200 (64 bits) |
| INFO | PowerShell | v7.6.2 |
| OK | .NET | Release=533509 (>=4.7.2) |
| OK | Disco | 32.1 GB libres. |
| WARN | PendingReboot | Pendiente: CBS RebootPending, WindowsUpdate RebootRequired, PendingFileRenameOperations |
| OK | Engine | NodeDeploy.ps1 presente (66.3 KB) |
| OK | Office XML | configuration.xml presente. |
| OK | Installer | AnyDesk                      7,7 MB  sig=Valid |
| WARN | Installer | AqNet                         66 MB  sig=NotSigned |
| OK | Installer | Nebula CertAgent            25,4 MB  sig=Valid |
| OK | Installer | MDR / Cortex XDR            41,7 MB  sig=Valid |
| OK | Installer | ESET Mgmt Agent             51,8 MB  sig=Valid |
| OK | Installer | Google Chrome               10,5 MB  sig=Valid |
| WARN | Installer | Autofirma                  130,4 MB  sig=UnknownError |
| OK | Installer | Bit4id Middleware           47,9 MB  sig=Valid |
| OK | Installer | PDFelement Business        570,9 MB  sig=Valid |
| OK | Installer | MitelConnect               151,3 MB  sig=Valid |
| OK | Installer | Microsoft 365 Apps           7,1 MB  sig=Valid |
| OK | Installer | iManage Agent Services       2,1 MB  sig=Valid |
| OK | Installer | iManage Drive              242,2 MB  sig=Valid |
| OK | Installer | iManage Drive Native         0,7 MB  sig=Valid |
| OK | Installer | iManage Work Desktop        70,1 MB  sig=Valid |
| OK | Inventory | Los 15 instaladores presentes. |
| OK | ESET INI | install_config.ini presente (6166 bytes) |
| INFO | Defender | RealTime=True AVEngine=1.1.26040.8 |
| WARN | Defender | Real-Time activo: puede ralentizar instaladores grandes (PDFelement 571MB). |

## Inventario instaladores

| App | Archivo | MB | Firma | Signer | SHA256 |
|-----|---------|----|-------|--------|--------|
| AnyDesk | `AnyDesk.msi` | 7,7 | Valid | AnyDesk Software GmbH | `5B95BC0104CA3722...` |
| AqNet | `AqNetInstalacion.msi` | 66 | NotSigned | - | `FA212A3A93636CF7...` |
| Nebula CertAgent | `nebula-certAgent-winx64-5.0.0.msi` | 25,4 | Valid | VINTEGRIS SL | `CB4D5081BDEE7AE0...` |
| MDR / Cortex XDR | `MDR_Windows_Andersen_8_2_x64.msi` | 41,7 | Valid | Palo Alto Networks (Netherlands) B.V. | `349C0B319C73D253...` |
| ESET Mgmt Agent | `eset_msi.msi` | 51,8 | Valid | "ESET | `ED3F289000CF126E...` |
| Google Chrome | `ChromeSetup.exe` | 10,5 | Valid | Google LLC | `C8C16A314A696EB4...` |
| Autofirma | `Autofirma_64_v1_9_installer.exe` | 130,4 | UnknownError | FIRMA DE CODIGO JAVA SECRETARIA GENERAL DE ADMINISTRACION DIGITAL | `BE78D202F4DA6408...` |
| Bit4id Middleware | `Bit4id_Middleware.exe` | 47,9 | Valid | BIT4ID SRL | `B1EE70D07AACABCD...` |
| PDFelement Business | `pdfelement_business-15066_10.1.5.exe` | 570,9 | Valid | "Wondershare Technology Group Co. | `CDB8C7FE0CD67BA0...` |
| MitelConnect | `MitelConnect.exe` | 151,3 | Valid | ShoreTel Inc. | `AC825A81C45F551B...` |
| Microsoft 365 Apps | `OfficeSetup.exe` | 7,1 | Valid | Microsoft Corporation | `C332C51EF04BD870...` |
| iManage Agent Services | `Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageAgentServices.exe` | 2,1 | Valid | iManage LLC | `0D77C46466F6CC01...` |
| iManage Drive | `Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManage Drive for Windows 10.10.0.410\iManageDriveSetup.exe` | 242,2 | Valid | iManage LLC | `BF8C11CF799C2B10...` |
| iManage Drive Native | `Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManageDrive Native 10.6.1.15\iManageDriveNative.exe` | 0,7 | Valid | iManage LLC | `DDBBF1B0B28D70D2...` |
| iManage Work Desktop | `Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe` | 70,1 | Valid | iManage LLC | `B36DD83BC8FAB3C0...` |

## Veredicto

**WARN - revisar warnings, continuar con precaucion**

