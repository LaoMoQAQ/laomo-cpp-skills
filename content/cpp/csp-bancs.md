---
title: "CSP-J/S 常用板子"
description: "算法竞赛常用代码模板，包含基础、数据结构、图论、数论、字符串和 DP。"
date: 2026-10-16
math: true
tags: ["C++", "算法", "模板", "CSP"]
---

## 一、基础

### 1. 快读

```cpp
inline int read() {
    int x = 0, f = 1; char c = getchar();
    while (!isdigit(c)) { if (c == '-') f = -1; c = getchar(); }
    while (isdigit(c)) { x = x * 10 + c - '0'; c = getchar(); }
    return x * f;
}
```

### 2. 离散化

```cpp
vector<int> a, b;
sort(b.begin(), b.end());
b.erase(unique(b.begin(), b.end()), b.end());
for (int &x : a)
    x = lower_bound(b.begin(), b.end(), x) - b.begin() + 1;
```

### 3. 整数二分：第一个 $\ge x$ 的位置

```cpp
int l = 0, r = n; // 区间 [l, r)
while (l < r) {
    int mid = (l + r) >> 1;
    if (a[mid] >= x) r = mid;
    else l = mid + 1;
}
return l;
```

### 4. 前缀和 / 差分

```cpp
// 前缀和
pre[i] = pre[i - 1] + a[i];
sum(l, r) = pre[r] - pre[l - 1];

// 差分
diff[l] += v;
diff[r + 1] -= v;
```

---

## 二、数据结构

### 1. 并查集

带路径压缩和按大小合并，单次操作均摊 $O(\alpha(n))$。

```cpp
struct DSU {
    vector<int> fa, sz;

    DSU(int n = 0) { init(n); }

    void init(int n) {
        fa.resize(n + 1);
        sz.assign(n + 1, 1);
        iota(fa.begin(), fa.end(), 0);
    }

    int find(int x) {
        return fa[x] == x ? x : fa[x] = find(fa[x]);
    }

    bool unite(int x, int y) {
        int rx = find(x), ry = find(y);
        if (rx == ry) return false;
        if (sz[rx] < sz[ry]) swap(rx, ry);
        fa[ry] = rx;
        sz[rx] += sz[ry];
        return true;
    }

    bool same(int x, int y) {
        return find(x) == find(y);
    }

    int size(int x) {
        return sz[find(x)];
    }
};
```

### 2. 树状数组：单点修改 + 区间查询

```cpp
struct BIT {
    int n;
    vector<long long> c;

    BIT(int n) : n(n), c(n + 1) {}

    void add(int x, long long v) {
        for (; x <= n; x += x & -x) c[x] += v;
    }

    long long sum(int x) {
        long long res = 0;
        for (; x; x -= x & -x) res += c[x];
        return res;
    }

    long long query(int l, int r) {
        return sum(r) - sum(l - 1);
    }
};
```

### 3. 线段树：区间加 + 区间求和

```cpp
struct SegTree {
    int n;
    vector<long long> sum, lazy;

    SegTree(int n) : n(n), sum(4 * n + 4), lazy(4 * n + 4) {}

    void pushup(int p) {
        sum[p] = sum[p << 1] + sum[p << 1 | 1];
    }

    void pushdown(int p, int l, int r) {
        if (!lazy[p]) return;
        int mid = (l + r) >> 1;
        sum[p << 1] += lazy[p] * (mid - l + 1);
        sum[p << 1 | 1] += lazy[p] * (r - mid);
        lazy[p << 1] += lazy[p];
        lazy[p << 1 | 1] += lazy[p];
        lazy[p] = 0;
    }

    void build(int p, int l, int r, vector<int>& a) {
        if (l == r) { sum[p] = a[l]; return; }
        int mid = (l + r) >> 1;
        build(p << 1, l, mid, a);
        build(p << 1 | 1, mid + 1, r, a);
        pushup(p);
    }

    void update(int p, int l, int r, int ql, int qr, long long v) {
        if (ql <= l && r <= qr) {
            sum[p] += v * (r - l + 1);
            lazy[p] += v;
            return;
        }
        pushdown(p, l, r);
        int mid = (l + r) >> 1;
        if (ql <= mid) update(p << 1, l, mid, ql, qr, v);
        if (qr > mid) update(p << 1 | 1, mid + 1, r, ql, qr, v);
        pushup(p);
    }

    long long query(int p, int l, int r, int ql, int qr) {
        if (ql <= l && r <= qr) return sum[p];
        pushdown(p, l, r);
        int mid = (l + r) >> 1;
        long long res = 0;
        if (ql <= mid) res += query(p << 1, l, mid, ql, qr);
        if (qr > mid) res += query(p << 1 | 1, mid + 1, r, ql, qr);
        return res;
    }
};
```

### 4. ST 表：RMQ

预处理 $O(n\log n)$，查询 $O(1)$。

```cpp
int st[N][20], lg[N];

void init() {
    lg[1] = 0;
    for (int i = 2; i <= n; i++) lg[i] = lg[i >> 1] + 1;
    for (int i = 1; i <= n; i++) st[i][0] = a[i];
    for (int j = 1; (1 << j) <= n; j++)
        for (int i = 1; i + (1 << j) - 1 <= n; i++)
            st[i][j] = max(st[i][j - 1], st[i + (1 << (j - 1))][j - 1]);
}

int query(int l, int r) {
    int k = lg[r - l + 1];
    return max(st[l][k], st[r - (1 << k) + 1][k]);
}
```

### 5. 单调队列：滑动窗口最大值

```cpp
deque<int> q;
for (int i = 1; i <= n; i++) {
    while (!q.empty() && q.front() <= i - k) q.pop_front();
    while (!q.empty() && a[q.back()] <= a[i]) q.pop_back();
    q.push_back(i);
    if (i >= k) cout << a[q.front()] << ' ';
}
```

### 6. Trie 字典树

```cpp
int son[N][26], cnt[N], idx;

void insert(char* str) {
    int p = 0;
    for (int i = 0; str[i]; i++) {
        int u = str[i] - 'a';
        if (!son[p][u]) son[p][u] = ++idx;
        p = son[p][u];
    }
    cnt[p]++;
}

int query(char* str) {
    int p = 0;
    for (int i = 0; str[i]; i++) {
        int u = str[i] - 'a';
        if (!son[p][u]) return 0;
        p = son[p][u];
    }
    return cnt[p];
}
```

---

## 三、图论

### 1. 链式前向星

```cpp
int head[N], to[M], nxt[M], w[M], idx;

void add(int u, int v, int ww) {
    to[++idx] = v;
    w[idx] = ww;
    nxt[idx] = head[u];
    head[u] = idx;
}
```

### 2. 拓扑排序

```cpp
queue<int> q;
for (int i = 1; i <= n; i++)
    if (!in[i]) q.push(i);

while (!q.empty()) {
    int u = q.front(); q.pop();
    topo[++cnt] = u;
    for (int i = head[u]; i; i = nxt[i]) {
        int v = to[i];
        if (--in[v] == 0) q.push(v);
    }
}
```

### 3. Dijkstra：堆优化

```cpp
priority_queue<pair<int, int>, vector<pair<int, int>>, greater<pair<int, int>>> pq;
vector<int> dist(n + 1, INF);
dist[s] = 0;
pq.push({0, s});

while (!pq.empty()) {
    int d = pq.top().first;
    int u = pq.top().second;
    pq.pop();
    if (d > dist[u]) continue;
    for (int i = head[u]; i; i = nxt[i]) {
        int v = to[i], ww = w[i];
        if (dist[v] > d + ww) {
            dist[v] = d + ww;
            pq.push({dist[v], v});
        }
    }
}
```

### 4. Floyd

时间复杂度 $O(n^3)$。

```cpp
for (int k = 1; k <= n; k++)
    for (int i = 1; i <= n; i++)
        for (int j = 1; j <= n; j++)
            d[i][j] = min(d[i][j], d[i][k] + d[k][j]);
```

### 5. Kruskal 最小生成树

```cpp
struct Edge { int u, v, w; } e[M];

sort(e + 1, e + m + 1, [](Edge a, Edge b) {
    return a.w < b.w;
});

DSU dsu(n);
int ans = 0, cnt = 0;
for (int i = 1; i <= m; i++) {
    if (dsu.unite(e[i].u, e[i].v)) {
        ans += e[i].w;
        if (++cnt == n - 1) break;
    }
}
```

### 6. LCA 倍增

```cpp
int dep[N], fa[N][20];

void dfs(int u, int p) {
    dep[u] = dep[p] + 1;
    fa[u][0] = p;
    for (int j = 1; j < 20; j++)
        fa[u][j] = fa[fa[u][j - 1]][j - 1];
    for (int i = head[u]; i; i = nxt[i]) {
        int v = to[i];
        if (v != p) dfs(v, u);
    }
}

int lca(int x, int y) {
    if (dep[x] < dep[y]) swap(x, y);
    for (int j = 19; j >= 0; j--)
        if (dep[fa[x][j]] >= dep[y]) x = fa[x][j];
    if (x == y) return x;
    for (int j = 19; j >= 0; j--)
        if (fa[x][j] != fa[y][j]) {
            x = fa[x][j];
            y = fa[y][j];
        }
    return fa[x][0];
}
```

### 7. Tarjan 强连通分量

```cpp
int dfn[N], low[N], stk[N], top, tim, scc[N], scc_cnt;
bool in_stk[N];

void tarjan(int u) {
    dfn[u] = low[u] = ++tim;
    stk[++top] = u;
    in_stk[u] = true;

    for (int i = head[u]; i; i = nxt[i]) {
        int v = to[i];
        if (!dfn[v]) {
            tarjan(v);
            low[u] = min(low[u], low[v]);
        } else if (in_stk[v]) {
            low[u] = min(low[u], dfn[v]);
        }
    }

    if (dfn[u] == low[u]) {
        int v;
        ++scc_cnt;
        do {
            v = stk[top--];
            in_stk[v] = false;
            scc[v] = scc_cnt;
        } while (v != u);
    }
}
```

### 8. 二分图匈牙利算法

```cpp
vector<int> g[N];
int match[N];
bool vis[N];

bool dfs(int u) {
    for (int v : g[u]) {
        if (vis[v]) continue;
        vis[v] = true;
        if (!match[v] || dfs(match[v])) {
            match[v] = u;
            return true;
        }
    }
    return false;
}

int max_match() {
    int res = 0;
    for (int i = 1; i <= n; i++) {
        memset(vis, 0, sizeof vis);
        if (dfs(i)) res++;
    }
    return res;
}
```

---

## 四、数论

### 1. 快速幂

计算 $a^b \bmod mod$，时间复杂度 $O(\log b)$。

```cpp
long long qpow(long long a, long long b, long long mod) {
    long long res = 1 % mod;
    while (b) {
        if (b & 1) res = res * a % mod;
        a = a * a % mod;
        b >>= 1;
    }
    return res;
}
```

### 2. 线性筛素数

时间复杂度 $O(n)$。

```cpp
vector<int> primes;
bool is_comp[N];

void sieve(int n) {
    for (int i = 2; i <= n; i++) {
        if (!is_comp[i]) primes.push_back(i);
        for (int p : primes) {
            if (i * p > n) break;
            is_comp[i * p] = true;
            if (i % p == 0) break;
        }
    }
}
```

### 3. 扩展欧几里得

```cpp
int exgcd(int a, int b, int &x, int &y) {
    if (!b) {
        x = 1; y = 0;
        return a;
    }
    int d = exgcd(b, a % b, y, x);
    y -= a / b * x;
    return d;
}
```

### 4. 逆元

```cpp
// 费马小定理，mod 为质数
long long inv = qpow(a, mod - 2, mod);

// exgcd
int x, y;
exgcd(a, mod, x, y);
x = (x % mod + mod) % mod;
```

### 5. 组合数：预处理阶乘逆元

```cpp
fact[0] = inv[0] = 1;
for (int i = 1; i <= n; i++)
    fact[i] = fact[i - 1] * i % mod;

inv[n] = qpow(fact[n], mod - 2, mod);
for (int i = n; i >= 1; i--)
    inv[i - 1] = inv[i] * i % mod;

C(n, m) = fact[n] * inv[m] % mod * inv[n - m] % mod;
```

---

## 五、字符串

### 1. KMP

```cpp
vector<int> kmp_next(string s) {
    int n = s.size();
    vector<int> nxt(n);
    for (int i = 1, j = 0; i < n; i++) {
        while (j && s[i] != s[j]) j = nxt[j - 1];
        if (s[i] == s[j]) j++;
        nxt[i] = j;
    }
    return nxt;
}
```

匹配：

```cpp
for (int i = 0, j = 0; i < text.size(); i++) {
    while (j && text[i] != pat[j]) j = nxt[j - 1];
    if (text[i] == pat[j]) j++;
    if (j == pat.size()) {
        // 匹配位置：i - pat.size() + 1
        j = nxt[j - 1];
    }
}
```

### 2. 字符串哈希

```cpp
typedef unsigned long long ull;
const ull base = 131;
ull h[N], p[N];

void init(string s) {
    p[0] = 1;
    for (int i = 1; i <= s.size(); i++) {
        h[i] = h[i - 1] * base + s[i - 1];
        p[i] = p[i - 1] * base;
    }
}

ull get(int l, int r) {
    return h[r] - h[l - 1] * p[r - l + 1];
}
```

### 3. Manacher

```cpp
string s, t;
int p[N];

void manacher() {
    t = "^#";
    for (char c : s) {
        t += c;
        t += '#';
    }
    t += '$';

    int n = t.size(), C = 0, R = 0;
    for (int i = 1; i < n - 1; i++) {
        p[i] = (R > i) ? min(R - i, p[2 * C - i]) : 1;
        while (t[i + p[i]] == t[i - p[i]]) p[i]++;
        if (i + p[i] > R) {
            C = i;
            R = i + p[i];
        }
    }
    // 最长回文长度 = max(p[i]) - 1
}
```

---

## 六、DP

### 1. 01 背包

```cpp
for (int i = 1; i <= n; i++)
    for (int j = m; j >= w[i]; j--)
        dp[j] = max(dp[j], dp[j - w[i]] + v[i]);
```

### 2. 完全背包

```cpp
for (int i = 1; i <= n; i++)
    for (int j = w[i]; j <= m; j++)
        dp[j] = max(dp[j], dp[j - w[i]] + v[i]);
```

### 3. 多重背包：二进制优化

```cpp
for (int i = 1; i <= n; i++) {
    int k = 1;
    while (k <= c[i]) {
        // 按 01 背包处理重量 k*w[i]，价值 k*v[i]
        c[i] -= k;
        k <<= 1;
    }
    if (c[i]) {
        // 按 01 背包处理重量 c[i]*w[i]，价值 c[i]*v[i]
    }
}
```

### 4. LIS 最长上升子序列：贪心 + 二分

时间复杂度 $O(n\log n)$。

```cpp
vector<int> d;
for (int x : a) {
    auto it = lower_bound(d.begin(), d.end(), x);
    if (it == d.end()) d.push_back(x);
    else *it = x;
}
cout << d.size() << "\n";
```

### 5. LCS 最长公共子序列

```cpp
for (int i = 1; i <= n; i++)
    for (int j = 1; j <= m; j++)
        if (a[i] == b[j])
            dp[i][j] = dp[i - 1][j - 1] + 1;
        else
            dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]);
```

### 6. 区间 DP

```cpp
for (int len = 2; len <= n; len++)
    for (int l = 1; l + len - 1 <= n; l++) {
        int r = l + len - 1;
        for (int k = l; k < r; k++)
            dp[l][r] = max(dp[l][r], dp[l][k] + dp[k + 1][r] + ...);
    }
```

### 7. 状压 DP：枚举子集

```cpp
for (int s = 1; s < (1 << n); s++)
    for (int sub = s; sub; sub = (sub - 1) & s) {
        // sub 是 s 的子集
    }
```