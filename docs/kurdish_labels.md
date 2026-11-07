# Sorani labels — native-speaker review

Mirror of `lib/speech/kurdish_labels.dart` and `lib/app/ui_strings.dart`.
A native Sorani speaker ticks **Verified** and corrects anything wrong. The
code is then updated and its `// REVIEW` comment removed.

## Object classes
Selected in D-014. All Sorani below is an unreviewed draft. Please check the
spelling, the indefinite form, and whether it is the word people actually use.

| Class id | COCO name | Sorani | Indefinite | «ـیش» form | Verified |
|---|---|---|---|---|---|
| 0 | person | کەس | کەسێک | کەسێکیش | ☐ |
| 2 | car | ئۆتۆمبێل | ئۆتۆمبێلێک | ئۆتۆمبێلێکیش | ☐ |
| 24 | backpack | جانتای پشت | جانتایەکی پشت | جانتایەکی پشتیش | ☐ |
| 26 | handbag | جانتا | جانتایەک | جانتایەکیش | ☐ |
| 39 | bottle | بوتڵ | بوتڵێک | بوتڵێکیش | ☐ |
| 41 | cup | پەرداخ | پەرداخێک | پەرداخێکیش | ☐ |
| 45 | bowl | قاپ | قاپێک | قاپێکیش | ☐ |
| 56 | chair | کورسی | کورسییەک | کورسییەکیش | ☐ |
| 57 | couch | قەنەفە | قەنەفەیەک | قەنەفەیەکیش | ☐ |
| 59 | bed | قەرەوێڵە | قەرەوێڵەیەک | قەرەوێڵەیەکیش | ☐ |
| 60 | dining table | مێز | مێزێک | مێزێکیش | ☐ |
| 61 | toilet | تەوالێت | تەوالێتێک | تەوالێتێکیش | ☐ |
| 62 | tv | تەلەفزیۆن | تەلەفزیۆنێک | تەلەفزیۆنێکیش | ☐ |
| 63 | laptop | لاپتۆپ | لاپتۆپێک | لاپتۆپێکیش | ☐ |
| 65 | remote | ڕیمۆت | ڕیمۆتێک | ڕیمۆتێکیش | ☐ |
| 67 | cell phone | مۆبایل | مۆبایلێک | مۆبایلێکیش | ☐ |
| 71 | sink | دەستشۆر | دەستشۆرێک | دەستشۆرێکیش | ☐ |
| 72 | refrigerator | سەلاجە | سەلاجەیەک | سەلاجەیەکیش | ☐ |
| 73 | book | کتێب | کتێبێک | کتێبێکیش | ☐ |
| 74 | clock | کاتژمێر | کاتژمێرێک | کاتژمێرێکیش | ☐ |

## Sentence pieces

Draft wording. Examples: «لەبەردەمت مێزێک هەیە.» · «لای چەپ مێزێک هەیە. پەرداخێکیش دەبینرێت.» · «لەبەردەمت مێزێک هەیە. پەرداخێک و کورسییەکیش دەبینرێن.» Please also check that these read naturally, and that «لەبەردەمت» is right for an object in the centre (CLAUDE.md also lists «لە ناوەڕاست»).

| Clip key | Sorani | Meaning | Verified |
|---|---|---|---|
| in_front | لەبەردەمت | "in front of you" | ☐ |
| exists | هەیە | "there is" | ☐ |
| and | و | "and" | ☐ |
| seen_one | دەبینرێت | "is seen" (one object) | ☐ |
| seen_many | دەبینرێن | "are seen" (several) | ☐ |
| nothing_detected | هیچ شتێک نەناسرایەوە | "nothing was recognised" | ☐ |

## Position words (given in CLAUDE.md)

| Position | Sorani | Verified |
|---|---|---|
| left | لای چەپ | ☐ |
| center | لە ناوەڕاست | ☐ |
| right | لای ڕاست | ☐ |

## UI strings

| Key | Sorani | English meaning | Verified |
|---|---|---|---|
| appTitle | بینینی کوردی | "Kurdish vision" (app name) | ☐ |
| preparing | ئامادە دەکرێت… | "Preparing…" | ☐ |
| running | ناسینەوەی شتەکان کار دەکات. | "Object recognition is running." | ☐ |
| paused | ناسینەوەی شتەکان ڕاگیراوە. | "Object recognition is paused." | ☐ |
| permissionDenied | ڕێگەی بەکارهێنانی کامێرا نەدراوە. لە ڕێکخستنەکانی مۆبایلەکەت ڕێگە بدە، پاشان پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە. | "Camera permission was not given. Allow it in your phone's settings, then touch the screen to try again." | ☐ |
| noCamera | هیچ کامێرایەک نەدۆزرایەوە. پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە. | "No camera was found. Touch the screen to try again." | ☐ |
| cameraError | هەڵەیەک لە کامێرادا ڕوویدا. پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە. | "A camera error occurred. Touch the screen to try again." | ☐ |
| modelError | ناسینەوەی شتەکان نەیتوانی دەست پێ بکات. پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە. | "Object recognition could not start. Touch the screen to try again." | ☐ |
| repeatAction | دووبارەکردنەوە | "Repeat" (screen-reader action) | ☐ |
| retryAction | هەوڵدانەوە | "Try again" (screen-reader action) | ☐ |
| pauseAction | ڕاگرتن | "Pause" (screen-reader action) | ☐ |
| resumeAction | دەستپێکردنەوە | "Resume" (screen-reader action) | ☐ |
| settings | ڕێکخستنەکان | "Settings" | ☐ |
| back | گەڕانەوە | "Back" | ☐ |
| settingsPlaceholder | ڕێکخستنەکان لە وەشانی داهاتوودا زیاد دەکرێن. | "Settings will be added in a later version." | ☐ |
| iOS camera permission | ئەم ئەپە کامێرا بەکاردەهێنێت بۆ ناسینەوەی ئەو شتانەی لەبەردەمتن. وێنەکان تەنها لەسەر مۆبایلەکەت شیدەکرێنەوە و هیچ شوێنێک نانێردرێن. | "This app uses the camera to recognise objects in front of you. Images are processed only on your phone and are never sent anywhere." | ☐ |
