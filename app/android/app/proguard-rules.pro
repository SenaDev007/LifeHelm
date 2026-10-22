# Règles R8/ProGuard — LifeHelm.
# Le plugin Gradle Flutter active la minification et le shrinkage de
# ressources PAR DÉFAUT en release (shouldShrinkResources) et fournit déjà
# les règles de conservation du moteur et de l'embedding.
# Les plugins tiers (firebase_messaging, flutter_local_notifications…)
# embarquent leurs propres règles « consumer » dans leurs AAR.
# Les conservations ci-dessous sont une ceinture de sécurité pour les
# composants déclarés dans le manifest et instanciés par réflexion.

# Récepteurs/services de notifications déclarés dans AndroidManifest.xml.
-keep class com.dexterous.** { *; }

# Services Firebase (FCM) instanciés par réflexion.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Sérialisation des messages FCM (données du briefing).
-keep class com.yehiortech.lifehelm.** { *; }

# Gson/Jackson éventuels côté plugins — évite la suppression de champs
# accédés par réflexion (règle générique standard).
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-dontwarn javax.annotation.**
