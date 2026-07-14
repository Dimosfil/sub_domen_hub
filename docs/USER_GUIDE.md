# Руководство пользователя Subdomain Hub

Subdomain Hub — это шлюз публикации и реестр целей хостинга. Он может собрать локальный проект или Git-репозиторий и загрузить готовый артефакт на настроенный поддомен либо legacy-путь через SFTP, FTP или FTPS.

## 1. Что понадобится

- Windows PowerShell.
- Python с пакетом `paramiko` для рекомендуемого SFTP-сценария.
- Доступ к хостингу и корректный удалённый путь.
- Идентификатор зарегистрированного проекта либо путь к локальному проекту.

Если `paramiko` отсутствует:

```powershell
python -m pip install --user paramiko
```

## 2. Локальная настройка SFTP

Создайте локальный конфигурационный файл из безопасного примера:

```powershell
Copy-Item .\tools\deploy\sftp.local.example.json .\tools\deploy\sftp.local.json
```

В `tools/deploy/sftp.local.json` укажите реальный `target.remotePath` и при необходимости настройте `pathRewrites`. Этот файл игнорируется Git и не должен коммититься.

Перед запуском задайте реквизиты через переменные окружения:

```powershell
$env:SUB_DOMEN_HUB_SFTP_HOST = "..."
$env:SUB_DOMEN_HUB_SFTP_USER = "..."
$env:SUB_DOMEN_HUB_SFTP_PASSWORD = "..."
```

Не передавайте пароль аргументом командной строки и не сохраняйте его в документации, логах или отслеживаемых файлах.

## 3. Публикация зарегистрированного проекта

Доступные цели перечислены в `tools/deploy/hosting-projects.json`. Сначала выполните безопасную проверку:

```powershell
.\tools\deploy\deploy.ps1 -Project <project-id> -DryRun
```

Проверьте в выводе:

- выбранный проект и режим публикации;
- исходную папку и build-команду;
- папку готового артефакта;
- удалённый путь назначения;
- список исключённых файлов.

Если всё правильно, запустите реальную публикацию:

```powershell
.\tools\deploy\deploy.ps1 -Project <project-id>
```

Для проекта, который должен остаться на legacy-пути:

```powershell
.\tools\deploy\deploy.ps1 -Project <project-id> -DeployMode legacy -DryRun
.\tools\deploy\deploy.ps1 -Project <project-id> -DeployMode legacy
```

## 4. Публикация локальной папки

Статический проект без сборки:

```powershell
.\tools\deploy\deploy.ps1 -SourcePath D:\path\to\site -SkipBuild -DryRun
```

Проект со сборкой:

```powershell
.\tools\deploy\deploy.ps1 `
  -SourcePath D:\path\to\project `
  -BuildCommand "npm ci; npm run build" `
  -OutputPath dist `
  -DryRun
```

После проверки повторите ту же команду без `-DryRun`.

## 5. Публикация Git-репозитория

```powershell
.\tools\deploy\deploy.ps1 `
  -GitUrl https://example.com/owner/repository.git `
  -Ref main `
  -BuildCommand "npm ci; npm run build" `
  -OutputPath dist `
  -DryRun
```

Не используйте URL со встроенным токеном или паролем.

## 6. Новый поддомен

Если сайт для поддомена ещё не создан, сначала изучите раздел `Subdomain Provisioning` в [техническом руководстве](deploy.md). Запускайте provisioning с `-DryRun` и переходите к реальному созданию только после проверки hostname и document root.

Добавление проекта в публичный каталог — отдельная операция. Следуйте [регламенту карточек](root-hub-project-cards.md): обычный деплой не даёт разрешения редактировать или публиковать внешний проект публичного хаба.

## 7. Важные правила безопасности

- Всегда выполняйте `-DryRun` перед первой публикацией и после изменения build-команды, output path или remote path.
- Скрипты перезаписывают совпадающие удалённые файлы, но не удаляют лишние файлы на сервере.
- Не коммитьте `*.local.json`, пароли, токены, приватные пути и журналы с секретами.
- Не меняйте `tools/deploy/hosting-projects.json`, если не уверены в целевом домене и режиме публикации.
- Удаление сайта, DNS-записей или файлов хостинга требует отдельного явного решения и не является частью обычного деплоя.

## 8. Если что-то не работает

- `No deploy config found` — создайте `tools/deploy/sftp.local.json` или `tools/deploy/ftp.local.json` из соответствующего примера.
- Ошибка импорта `paramiko` — установите пакет командой из раздела 1.
- Не найден project id — проверьте `tools/deploy/hosting-projects.json`.
- Неверный удалённый путь — остановитесь, исправьте локальный конфиг и снова выполните `-DryRun`.
- Сборка не создала ожидаемую папку — проверьте `-BuildCommand` и `-OutputPath`.

Полный список параметров и операционные детали находятся в [docs/deploy.md](deploy.md).
