.class public Ls23tweaks/H;
.super Ljava/lang/Object;


# direct methods
.method public static f(Lcom/android/server/pm/Computer;ILcom/android/server/pm/pkg/PackageStateInternal;)Z
    .locals 6

    const/4 v3, 0x0

    invoke-interface {p2}, Lcom/android/server/pm/pkg/PackageState;->getPackageName()Ljava/lang/String;

    move-result-object v0

    const-string/jumbo v1, "me.weishu.kernelsu"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v2

    if-nez v2, :cond_0

    return v3

    :cond_0
    invoke-static {p1}, Landroid/os/UserHandle;->getAppId(I)I

    move-result v2

    const/16 v4, 0x2710

    if-ge v2, v4, :cond_1

    return v3

    :cond_1
    invoke-interface {p0, p1}, Lcom/android/server/pm/Computer;->getPackagesForUid(I)[Ljava/lang/String;

    move-result-object v4

    if-eqz v4, :cond_3

    array-length v5, v4

    const/4 v2, 0x0

    :goto_0
    if-ge v2, v5, :cond_3

    aget-object v0, v4, v2

    const-string v1, "df.root"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_2

    const-string/jumbo v1, "me.weishu.kernelsu"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_2

    const-string v1, "com.sec.android.app.launcher"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :cond_2

    add-int/lit8 v2, v2, 0x1

    goto :goto_0

    :cond_2
    return v3

    :cond_3
    const/4 v0, 0x1

    return v0
.end method
