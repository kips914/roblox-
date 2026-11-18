# Интеграция в Roblox Studio

## 1. Синхронизация проекта

Проект построен по структуре [Rojo](https://github.com/rojo-rbx/rojo). Откройте его корень и выполните:

```bash
rojo serve default.project.json
```

Подключите плагин Rojo в Studio. После синхронизации должны появиться:

- `ReplicatedStorage/Combat`;
- `ServerScriptService/Combat/CombatBootstrap`;
- `StarterPlayer/StarterPlayerScripts/CombatClient`.

Запускайте через **Test → Start** или Play; в Output должно появиться сообщение `[Combat] Ballistics system started ...`.

## 2. Превращаем Tool в пушку

В `StarterPack` добавьте обычный `Tool`.

1. Поставьте **Attribute** `CombatWeapon` (Boolean) = `true`.
2. Добавьте Handle/модель ствола и `Attachment` с именем `Muzzle` на срезе канала. Ось LookVector Attachment должна смотреть вперёд.
3. Скопируйте `Combat/Examples/WeaponConfig` в Tool и назовите модуль `WeaponConfig`.
4. Добавьте на Tool атрибуты боезапаса. Имена строго совпадают с `Ammo_<id>`:

   ```text
   Ammo_AP_30MM     Number 48
   Ammo_HE_30MM     Number 24
   Ammo_HEAT_30MM   Number 8
   Ammo_APFSDS_30MM Number 12
   ```

5. По желанию задайте `AmmoInMagazine` (Number), `LoadedShellType` (String), `SelectedShellType` (String) для уже заряженного оружия. Иначе игрок нажмёт `R`.

`WeaponConfig` является нормальным ModuleScript под Tool. Его поля описаны в README. Значения в одноимённых атрибутах Tool имеют приоритет над соответствующими полями конфигурации.

## 3. Расставляем броню

Для бронеплиты добавьте `ArmorThicknessMm`, `ArmorMaterial`, `ArmorIntegrity`. Например, у детали корпуса:

```text
ArmorThicknessMm  Number  38
ArmorMaterial     String  Steel
ArmorIntegrity    Number  1
ArmorHitPointsJoules Number 420000
```

Атрибуты можно поставить и на Model. Это удобно для каски/жилета с несколькими деталями. При каждом попадании система обновляет `ArmorIntegrity`, поэтому её легко вывести в интерфейс или использовать в эффектах повреждений.

## 4. Проверка в мультиплеере

Используйте **Test → Start** с 2 игроками. Оружейные запросы идут от клиента, но сервер:

- требует, чтобы Tool был экипирован именно этим игроком;
- берёт начало выстрела только из серверного `Muzzle`;
- ограничивает темп огня;
- ведёт магазин и резервные боеприпасы;
- сам делает raycast с малыми подшагами;
- сам вызывает `Humanoid:TakeDamage`.

Поэтому изменение LocalScript не даёт игроку произвольный урон, скорострельность или выстрел из чужого Tool.

## Тюнинг

- **Непробиваемая карта:** для тонких декоративных объектов задайте небольшое `ArmorThicknessMm`, иначе наименьшая геометрическая толщина Roblox детали используется как реальный масштаб.
- **Слишком сильные рикошеты:** уменьшите `ricochetStartAngleDegrees`? Нет — *увеличение* порога делает рикошеты реже; уменьшение делает их чаще.
- **Броня быстро деградирует:** увеличьте `ArmorHitPointsJoules` или уменьшите `armorDamageFactor` у боеприпаса.
- **Клиентские эффекты:** это только `CombatClient`. Их можно заменять частицами/звуками, не изменяя авторитетность сервера.
