---
title: PD Scheduling Best Practices
summary: Learn best practice and strategy for PD scheduling.
---

# PDスケジューリングのベストプラクティス {#pd-scheduling-best-practices}

このドキュメントでは、アプリケーションを容易にするための一般的なシナリオを通じて、PDスケジューリングの原則と戦略について詳しく説明します。このドキュメントは、次のコアコンセプトを使用してTiDB、TiKV、およびPDの基本を理解していることを前提としています。

-   [リーダー/フォロワー/学習者](/glossary.md#leaderfollowerlearner)
-   [オペレーター](/glossary.md#operator)
-   [オペレーターステップ](/glossary.md#operator-step)
-   [保留中/ダウン](/glossary.md#pendingdown)
-   [リージョン/ピア/Raftグループ](/glossary.md#regionpeerraft-group)
-   [リージョン分割](/glossary.md#region-split)
-   [スケジューラー](/glossary.md#scheduler)
-   [お店](/glossary.md#store)

> **ノート：**
>
> このドキュメントは当初、TiDB3.0を対象としています。一部の機能は以前のバージョン（2.x）ではサポートされていませんが、基盤となるメカニズムは類似しており、このドキュメントは引き続き参照として使用できます。

## PDスケジューリングポリシー {#pd-scheduling-policies}

このセクションでは、スケジューリングシステムに関連する原則とプロセスを紹介します。

### スケジューリングプロセス {#scheduling-process}

スケジューリングプロセスには通常、次の3つのステップがあります。

1.  情報を収集する

    各TiKVノードは、定期的に2種類のハートビートをPDに報告します。

    -   `StoreHeartbeat` ：ディスク容量、使用可能なストレージ、読み取り/書き込みトラフィックなど、ストアの全体的な情報が含まれます
    -   `RegionHeartbeat` ：各リージョンの範囲、ピアディストリビューション、ピアステータス、データボリューム、読み取り/書き込みトラフィックなど、リージョンの全体的な情報が含まれます

    PDは、スケジュール決定のためにこの情報を収集して復元します。

2.  演算子を生成する

    さまざまなスケジューラーが、以下の考慮事項を考慮して、独自のロジックと要件に基づいて演算子を生成します。

    -   異常な状態（切断、ダウン、ビジー、スペース不足）のストアにピアを追加しないでください
    -   異常な状態の領域のバランスをとらないでください
    -   リーダーを保留中のピアに転送しないでください
    -   リーダーを直接削除しないでください
    -   さまざまなリージョンピアの物理的な分離を壊さないでください
    -   ラベルプロパティなどの制約に違反しないでください

3.  演算子を実行する

    演算子を実行するための一般的な手順は次のとおりです。

    1.  生成されたオペレーターは、最初に`OperatorController`によって管理されるキューに参加します。

    2.  `OperatorController`は、オペレーターをキューから取り出し、構成に基づいて一定量の並行性で実行します。このステップでは、各オペレーターステップを対応するリージョンリーダーに割り当てます。

    3.  オペレーターは「終了」または「タイムアウト」としてマークされ、キューから削除されます。

### 負荷分散 {#load-balancing}

リージョンは、負荷分散を実現するために主に`balance-leader`および`balance-region`のスケジューラーに依存しています。両方のスケジューラーは、クラスタのすべてのストアに均等にリージョンを分散することを目標として`balance-leader` `balance-region`が、個別に焦点を当てています。 。

`balance-leader`と`balance-region`は、同様のスケジューリングプロセスを共有します。

1.  リソースの可用性に応じてストアを評価します。
2.  `balance-leader`または`balance-region`は、リーダーまたはピアをスコアの高いストアからスコアの低いストアに絶えず転送します。

ただし、評価方法は異なります。 `balance-leader`は店舗のリーダーに対応するすべての地域サイズの合計を使用しますが、 `balance-region`の方法は比較的複雑です。各ノードの特定のストレージ容量に応じて、 `balance-region`の評価方法は次のようになります。

-   十分なストレージがある場合のデータ量に基づきます（ノード間のデータ分散のバランスを取るため）。
-   ストレージが不十分な場合に使用可能なストレージに基づきます（異なるノードでのストレージの可用性のバランスを取るため）。
-   どちらの状況も当てはまらない場合は、上記の2つの要素の加重和に基づきます。

ノードによってパフォーマンスが異なる可能性があるため、ストアごとに負荷分散の重みを設定することもできます。 `leader-weight`と`region-weight`は、それぞれリーダーの重みと領域の重みを制御するために使用されます（両方のデフォルトで「1」）。たとえば、ストアの`leader-weight`が「2」に設定されている場合、スケジューリングが安定した後、ノード上のリーダーの数は他のノードの数の約2倍になります。同様に、ストアの`leader-weight`が「0.5」に設定されている場合、ノード上のリーダーの数は他のノードの約半分になります。

### ホットリージョンのスケジューリング {#hot-regions-scheduling}

ホットリージョンのスケジューリングには、 `hot-region-scheduler`を使用します。 TiDB v3.0以降、プロセスは次のように実行されます。

1.  ストアから報告された情報に基づいて、特定の期間に特定のしきい値を超える読み取り/書き込みトラフィックを判別することにより、ホットリージョンをカウントします。

2.  負荷分散と同様の方法で、これらのリージョンを再分散します。

ホット書き込みリージョンの場合、 `hot-region-scheduler`はリージョンピアとリーダーの両方を再配布しようとします。ホットリードリージョンの場合、 `hot-region-scheduler`はリージョンリーダーのみを再配布します。

### クラスタートポロジの認識 {#cluster-topology-awareness}

クラスタトポロジの認識により、PDはリージョンのレプリカを可能な限り配布できます。これが、TiKVが高可用性とディザスタリカバリ機能を保証する方法です。 PDは、バックグラウンドのすべての領域を継続的にスキャンします。 PDは、リージョンの分散が最適でないことを検出すると、ピアを置き換えてリージョンを再分散する演算子を生成します。

領域分布をチェックするコンポーネントは`replicaChecker`です。これは、無効にできないことを除いてスケジューラーに似ています。 `location-labels`の構成に基づく`replicaChecker`のスケジュール。たとえば、 `[zone,rack,host]`はクラスタの3層トポロジーを定義します。 PDは、最初に異なるゾーンに、またはゾーンが不十分な場合は異なるラックに（たとえば、3つのレプリカに対して2つのゾーン）、ラックが不十分な場合は異なるホストに、リージョンピアをスケジュールしようとします。

### スケールダウンと障害回復 {#scale-down-and-failure-recovery}

スケールダウンとは、ストアをオフラインにし、コマンドを使用して「オフライン」としてマークするプロセスを指します。 PDは、スケジューリングによってオフラインノード上のリージョンを他のノードに複製します。障害回復は、ストアに障害が発生して回復できない場合に適用されます。この場合、対応するストアにピアが分散されているリージョンではレプリカが失われる可能性があり、PDが他のノードに補充する必要があります。

スケールダウンと障害回復のプロセスは基本的に同じです。 `replicaChecker`は、異常な状態にあるリージョンピアを検出し、正常なストアで異常なピアを新しいピアと交換するためのオペレーターを生成します。

### リージョンマージ {#region-merge}

リージョンマージとは、隣接する小さなリージョンをマージするプロセスを指します。これは、データ削除後の多数の小さな領域または空の領域による不要なリソース消費を回避するのに役立ちます。領域のマージは`mergeChecker`によって実行されます。これは`replicaChecker`と同様の方法で処理されます。PDはバックグラウンドですべての領域を継続的にスキャンし、隣接する小さな領域が見つかったときに演算子を生成します。

具体的には、新しく分割されたリージョンが[`split-merge-interval`](/pd-configuration-file.md#split-merge-interval) （デフォルトでは`1h` ）の値を超えて存在する場合、次の条件のいずれかが発生すると、このリージョンはリージョンマージスケジューリングをトリガーします。

-   この領域のサイズは、 [`max-merge-region-size`](/pd-configuration-file.md#max-merge-region-size)の値（デフォルトでは20 MiB）よりも小さいです。

-   このリージョンのキーの数は、値[`max-merge-region-keys`](/pd-configuration-file.md#max-merge-region-keys) （デフォルトでは200,000）よりも少なくなっています。

## スケジュールステータスのクエリ {#query-scheduling-status}

メトリック、pd-ctl、およびログを介して、スケジューリングシステムのステータスを確認できます。このセクションでは、メトリックとpd-ctlのメソッドを簡単に紹介します。詳細については、 [PDモニタリングメトリクス](/grafana-pd-dashboard.md)と[PD Control](/pd-control.md)を参照してください。

### オペレーターのステータス {#operator-status}

**Grafana PD / Operator**ページには、オペレーターに関するメトリックが表示されます。その中には、次のものがあります。

-   オペレーター作成のスケジュール：オペレーター作成情報
-   オペレーターの終了時間：各オペレーターが消費する実行時間
-   オペレーターステップ期間：オペレーターステップによって消費された実行時間

次のコマンドでpd-ctlを使用して、演算子を照会できます。

-   `operator show` ：現在のスケジューリングタスクで生成されたすべての演算子を照会します
-   `operator show [admin | leader | region]` ：タイプ別に演算子を照会します

### バランス状態 {#balance-status}

**Grafana PD / 統計 -Balance**ページには、負荷分散に関するメトリックが表示されます。その中には、次のものがあります。

-   ストアリーダー/地域スコア：各ストアのスコア
-   ストアリーダー/リージョン数：各ストアのリーダー/リージョンの数
-   利用可能なストア：各ストアで利用可能なストレージ

pd-ctlのstoreコマンドを使用して、各ストアの残高ステータスを照会できます。

### ホットリージョンのステータス {#hot-region-status}

**Grafana PD / 統計ホットスポット**ページには、ホットリージョンに関するメトリックが表示されます。

-   ホット書き込み領域のリーダー/ピア分布：ホット書き込み領域のリーダー/ピア分布
-   ホットリードリージョンのリーダー分布：ホットリードリージョンのリーダー分布

次のコマンドでpd-ctlを使用して、ホットリージョンのステータスを照会することもできます。

-   `hot read` ：ホットリード領域を照会します
-   `hot write` ：ホット書き込み領域を照会します
-   `hot store` ：店舗ごとの暑い地域の分布を照会します
-   `region topread [limit]` ：上位の読み取りトラフィックがあるリージョンを照会します
-   `region topwrite [limit]` ：書き込みトラフィックが最も多いリージョンを照会します

### 地域の健康 {#region-health}

**Grafana PD / Cluster / Region health**パネルには、異常状態のリージョンに関するメトリックが表示されます。

地域チェックコマンドでpd-ctlを使用して、異常状態の地域のリストを照会できます。

-   `region check miss-peer` ：十分なピアがないリージョンを照会します
-   `region check extra-peer` ：追加のピアがあるリージョンを照会します
-   `region check down-peer` ：ダウンピアのあるリージョンを照会します
-   `region check pending-peer` ：保留中のピアがあるリージョンを照会します

## スケジューリング戦略を制御する {#control-scheduling-strategy}

pd-ctlを使用して、次の3つの側面からスケジューリング戦略を調整できます。詳細については、 [PD Control](/pd-control.md)を参照してください。

### スケジューラを手動で追加/削除 {#add-delete-scheduler-manually}

PDは、pd-ctlを介して直接スケジューラーを動的に追加および削除することをサポートします。例えば：

-   `scheduler show` ：システムで現在実行中のスケジューラーを表示します
-   `scheduler remove balance-leader-scheduler` ：balance-leader-schedulerを削除（無効化）します
-   `scheduler add evict-leader-scheduler 1` ：ストア1のすべてのリーダーを削除するスケジューラーを追加します

### 演算子を手動で追加/削除 {#add-delete-operators-manually}

PDは、pd-ctlを介して直接演算子を追加または削除することもサポートしています。例えば：

-   `operator add add-peer 2 5` ：ストア5のリージョン2にピアを追加します
-   `operator add transfer-leader 2 5` ：リージョン2のリーダーをストア5に移行します
-   `operator add split-region 2` ：リージョン2を2つのリージョンに均等に分割します
-   `operator remove 2` ：リージョン2で現在保留中のオペレーターを削除します

### スケジューリングパラメータを調整します {#adjust-scheduling-parameter}

pd-ctlの`config show`コマンドを使用してスケジューリング構成を確認し、 `config set {key} {value}`を使用して値を調整できます。一般的な調整は次のとおりです。

-   `leader-schedule-limit` ：リーダースケジューリングの転送の同時実行性を制御します
-   `region-schedule-limit` ：ピアスケジューリングの追加/削除の同時実行性を制御します
-   `enable-replace-offline-replica` ：ノードをオフラインにするスケジューリングを有効にするかどうかを決定します
-   `enable-location-replacement` ：リージョンの分離レベルを処理するスケジューリングを有効にするかどうかを決定します
-   `max-snapshot-count` ：各ストアのスナップショットの送受信の最大同時実行性を制御します

## 一般的なシナリオでのPDスケジューリング {#pd-scheduling-in-common-scenarios}

このセクションでは、いくつかの一般的なシナリオを通じて、PDスケジューリング戦略のベストプラクティスを示します。

### リーダー/地域は均等に分散されていません {#leaders-regions-are-not-evenly-distributed}

PDの評価メカニズムは、異なるストアのリーダー数とリージョン数が負荷分散ステータスを完全に反映できないことを決定します。したがって、TiKVの実際の負荷またはストレージ使用量から負荷の不均衡があるかどうかを確認する必要があります。

リーダー/地域が均等に分散されていないことを確認したら、さまざまな店舗の評価を確認する必要があります。

異なる店舗のスコアが近い場合、PDはリーダー/地域が均等に分散していると誤って信じていることを意味します。考えられる理由は次のとおりです。

-   負荷の不均衡を引き起こす高温領域があります。この場合、 [ホットリージョンのスケジューリング](#hot-regions-are-not-evenly-distributed)に基づいてさらに分析する必要があります。
-   空のリージョンや小さなリージョンが多数あるため、さまざまな店舗のリーダーの数に大きな違いがあり、 Raftストアに高いプレッシャーがかかります。これは、 [リージョンマージ](#region-merge-is-slow)のスケジューリングの時間です。
-   ハードウェアとソフトウェアの環境は店舗によって異なります。それに応じて`leader-weight`と`region-weight`の値を調整して、リーダー/地域の分布を制御できます。
-   その他の不明な理由。それでも、 `leader-weight`と`region-weight`の値を調整して、リーダー/地域の分布を制御できます。

店舗ごとに評価に大きな違いがある場合は、オペレーターの生成と実行に特に重点を置いて、オペレーター関連の指標を調べる必要があります。主な状況は2つあります。

-   演算子は正常に生成されますが、スケジューリングプロセスが遅い場合は、次の可能性があります。

    -   スケジューリング速度は、負荷分散の目的でデフォルトで制限されています。通常のサービスに大きな影響を与えることなく、 `leader-schedule-limit`または`region-schedule-limit`をより大きな値に調整できます。さらに、 `max-pending-peer-count`と`max-snapshot-count`で指定された制限を適切に緩和することもできます。
    -   他のスケジューリングタスクが同時に実行されているため、バランシングが遅くなります。この場合、バランシングが他のスケジューリングタスクよりも優先される場合は、他のタスクを停止するか、それらの速度を制限することができます。たとえば、バランシングの進行中に一部のノードをオフラインにすると、両方の操作で`region-schedule-limit`のクォータが消費されます。この場合、スケジューラーの速度を制限してノードを削除するか、単に`enable-replace-offline-replica = false`に設定して一時的に無効にすることができます。
    -   スケジューリングプロセスが遅すぎます。**オペレーターステップ期間**メトリックをチェックして、原因を確認できます。通常、スナップショットの送受信を伴わないステップ（ `TransferLeader`など）はミリ秒単位で完了する必要があり`RemovePeer`が、スナップショットを含むステップ（ `PromoteLearner`や`AddLearner` `AddPeer` ）は数十秒で完了すると予想されます。明らかに持続時間が長すぎる場合は、TiKVへの高圧やネットワークのボトルネックなどが原因である可能性があり、特定の分析が必要です。

-   PDは、対応するバランシングスケジューラの生成に失敗します。考えられる理由は次のとおりです。

    -   スケジューラーがアクティブ化されていません。たとえば、対応するスケジューラが削除されるか、その制限が「0」に設定されます。
    -   その他の制約。たとえば、システムの`evict-leader-scheduler`は、リーダーが対応するストアに移行するのを防ぎます。または、labelプロパティが設定されているため、一部のストアはリーダーを拒否します。
    -   クラスタトポロジからの制限。たとえば、3つのデータセンターにまたがる3つのレプリカのクラスタでは、レプリカが分離されているため、各リージョンの3つのレプリカが異なるデータセンターに分散されます。これらのデータセンター間でストアの数が異なる場合、スケジューリングは各データセンター内でのみバランスの取れた状態に到達できますが、グローバルにバランスが取れているわけではありません。

### ノードをオフラインにするのは遅い {#taking-nodes-offline-is-slow}

このシナリオでは、関連するメトリックを介して演算子の生成と実行を調べる必要があります。

演算子が正常に生成されたが、スケジューリングプロセスが遅い場合、考えられる理由は次のとおりです。

-   スケジューリング速度はデフォルトで制限されています。 `leader-schedule-limit`または`replica-schedule-limit`をより大きな値に調整できます。同様に、 `max-pending-peer-count`および`max-snapshot-count`の制限を緩めることを検討できます。
-   他のスケジューリングタスクが同時に実行され、システム内のリソースを求めて競争しています。 [リーダー/地域は均等に分散されていません](#leadersregions-are-not-evenly-distributed)で解決策を参照できます。
-   単一のノードをオフラインにすると、処理される多数のリージョンリーダー（3つのレプリカの構成では約1/3）がノードに分散され、削除されます。したがって、速度は、この単一ノードによってスナップショットが生成される速度によって制限されます。リーダーを移行するために手動で`evict-leader-scheduler`を追加することにより、速度を上げることができます。

対応する演算子が生成に失敗した場合、考えられる理由は次のとおりです。

-   オペレータが停止するか、 `replica-schedule-limit`が「0」に設定されます。
-   リージョンの移行に適切なノードはありません。たとえば、（同じラベルの）置換ノードの使用可能な容量サイズが20％未満の場合、PDは、そのノードのストレージが不足しないようにスケジューリングを停止します。このような場合、スペースを解放するには、ノードを追加するか、一部のデータを削除する必要があります。

### ノードをオンラインにするのは遅い {#bringing-nodes-online-is-slow}

現在、ノードのオンライン化は、バランスリージョンメカニズムによってスケジュールされています。トラブルシューティングについては、 [リーダー/地域は均等に分散されていません](#leadersregions-are-not-evenly-distributed)を参照してください。

### 暑い地域は均等に分散されていません {#hot-regions-are-not-evenly-distributed}

ホットリージョンのスケジューリングの問題は、通常、次のカテゴリに分類されます。

-   ホットリージョンはPDメトリックを介して監視できますが、スケジューリング速度はホットリージョンを時間内に再配布するのに追いつくことができません。

    **解決策**： `hot-region-schedule-limit`をより大きな値に調整し、他のスケジューラーの制限クォータを減らして、ホットリージョンのスケジューリングを高速化します。または、 `hot-region-cache-hits-threshold`を小さい値に調整して、PDがトラフィックの変化に対してより敏感になるようにすることもできます。

-   単一の領域に形成されたホットスポット。たとえば、小さなテーブルは大量のリクエストによって集中的にスキャンされます。これは、PDメトリックからも検出できます。実際に単一のホットスポットを分散することはできないため、このような領域を分割するには、手動で`split-region`演算子を追加する必要があります。

-   一部のノードの負荷は、システム全体のボトルネックとなるTiKV関連のメトリックからの他のノードの負荷よりも大幅に高くなります。現在、PDはトラフィック分析のみを介してホットスポットをカウントするため、特定のシナリオではPDがホットスポットを識別できない可能性があります。たとえば、一部の地域で集中的なポイントルックアップ要求がある場合、トラフィックで検出することは明らかではないかもしれませんが、それでも高いQPSはキーモジュールのボトルネックにつながる可能性があります。

    **解決策**：まず、特定のビジネスに基づいてホットリージョンが形成されるテーブルを見つけます。次に、 `scatter-range-scheduler`のスケジューラーを追加して、このテーブルのすべての領域を均等に分散させます。 TiDBは、この操作を簡素化するためにHTTPAPIにインターフェイスも提供します。詳細については、 [TiDB HTTP API](https://github.com/pingcap/tidb/blob/master/docs/tidb_http_api.md)を参照してください。

### リージョンのマージが遅い {#region-merge-is-slow}

低速スケジューリングと同様に、リージョンマージの速度は、 `merge-schedule-limit`と`region-schedule-limit`の構成によって制限される可能性が高いか、リージョンマージスケジューラが他のスケジューラと競合しています。具体的には、ソリューションは次のとおりです。

-   システムに多数の空の領域があることがメトリックからわかっている場合は、 `max-merge-region-size`と`max-merge-region-keys`を小さい値に調整して、マージを高速化できます。これは、マージプロセスにレプリカの移行が含まれるため、マージする領域が小さいほど、マージが高速になるためです。マージ演算子がすでに迅速に生成されている場合は、プロセスをさらに高速化するために、 `patrol-region-interval`から`10ms`に設定できます（この構成項目のデフォルト値は、v5.3.0以降のバージョンのTiDBでは`10ms`です）。これにより、CPU消費量が増える代わりに、領域スキャンが高速になります。

-   多くのテーブルが作成されてから空になりました（切り捨てられたテーブルを含む）。分割テーブル属性が有効になっている場合、これらの空のリージョンをマージすることはできません。次のパラメータを調整することにより、この属性を無効にできます。

    -   TiKV： `split-region-on-table`を`false`に設定します。パラメータを動的に変更することはできません。
    -   PD： PD Controlを使用して、クラスタの状況に必要なパラメーターを設定します。

        -   クラスタにTiDBインスタンスがなく、値[`key-type`](/pd-control.md#config-show--set-option-value--placement-rules)が`raw`または`txn`に設定されているとします。この場合、PDは、 `enable-cross-table-merge setting`の値に関係なく、テーブル間でリージョンをマージできます。 `key-type`パラメータは動的に変更できます。

        
        ```bash
        config set key-type txn
        ```

        -   クラスタにTiDBインスタンスがあり、値`key-type`が`table`に設定されているとします。この場合、PDは、値`enable-cross-table-merge`が`true`に設定されている場合にのみ、テーブル間でリージョンをマージできます。 `key-type`パラメータは動的に変更できます。

        
        ```bash
        config set enable-cross-table-merge true
        ```

        変更が有効にならない場合は、 [FAQ -TiKV / PDの変更された`toml`構成が有効にならないのはなぜですか？](/faq/deploy-and-maintain-faq.md#why-the-modified-toml-configuration-for-tikvpd-does-not-take-effect)を参照してください。

        > **ノート：**
        >
        > 配置ルールを有効にした後、デコードの失敗を回避するために値`key-type`を適切に切り替えます。

v3.0.4およびv2.1.16以前の場合、リージョンの`approximate_keys`は特定の状況で不正確であり（ほとんどはテーブルを削除した後に発生します）、キーの数が`max-merge-region-keys`の制約を破ります。この問題を回避するには、 `max-merge-region-keys`をより大きな値に調整します。

### TiKVノードのトラブルシューティング {#troubleshoot-tikv-node}

TiKVノードに障害が発生した場合、PDはデフォルトで、対応するノードを30分後に**ダウン**状態に設定し（構成項目`max-store-down-time`でカスタマイズ可能）、関連するリージョンのレプリカのバランスを取り直します。

実際には、ノードの障害が回復不能と見なされた場合は、すぐにオフラインにすることができます。これにより、PDは別のノードですぐにレプリカを補充し、データ損失のリスクを軽減します。対照的に、ノードが回復可能であると見なされても、30分以内に回復を実行できない場合は、タイムアウト後にレプリカとリソースの無駄が不要に補充されないように、一時的に`max-store-down-time`をより大きな値に調整できます。

TiDB v5.2.0では、TiKVは低速TiKVノード検出のメカニズムを導入しています。このメカニズムは、TiKVで要求をサンプリングすることにより、1から100の範囲のスコアを算出します。スコアが80以上のTiKVノードは低速としてマークされます。 [`evict-slow-store-scheduler`](/pd-control.md#scheduler-show--add--remove--pause--resume--config)を追加して、低速ノードを検出およびスケジュールできます。 1つのTiKVのみが低速として検出され、低速スコアが上限（デフォルトでは100）に達すると、このノードのリーダーが削除されます（ `evict-leader-scheduler`の効果と同様）。