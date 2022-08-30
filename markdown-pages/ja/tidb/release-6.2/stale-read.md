---
title: Usage Scenarios of Stale Read
summary: Learn about Stale Read and its usage scenarios.
---

# Stale Read の使用シナリオ {#usage-scenarios-of-stale-read}

このドキュメントでは、Stale Read の使用シナリオについて説明します。 Stale Read は、TiDB に保存されているデータの履歴バージョンを読み取るために TiDB が適用するメカニズムです。このメカニズムを使用すると、特定の時点または指定された時間範囲内の対応する履歴データを読み取ることができるため、ストレージ ノード間のデータ レプリケーションによって生じるレイテンシを節約できます。

Stale Read を使用している場合、TiDB はデータ読み取り用のレプリカをランダムに選択します。つまり、すべてのレプリカをデータ読み取りに使用できます。アプリケーションが非リアルタイム データの読み取りを許容できない場合は、Stale Read を使用しないでください。そうしないと、レプリカから読み取られたデータが、TiDB に書き込まれた最新のデータではない可能性があります。

## シナリオ例 {#scenario-examples}

<CustomContent platform="tidb">

-   シナリオ 1: トランザクションに読み取り操作のみが含まれ、データの古さをある程度許容できる場合は、Stale Read を使用して履歴データを取得できます。 TiDB は Stale Read を使用して、リアルタイムのパフォーマンスをいくらか犠牲にしてクエリ要求を任意のレプリカに送信するため、クエリ実行のスループットが向上します。特に小さなテーブルがクエリされるいくつかのシナリオでは、強力な一貫性のある読み取りが使用されると、リーダーが特定のストレージ ノードに集中し、クエリのプレッシャーがそのノードにも集中する可能性があります。したがって、そのノードがクエリ全体のボトルネックになる可能性があります。ただし、古い読み取りは、クエリの全体的なスループットを向上させ、クエリのパフォーマンスを大幅に向上させることができます。

-   シナリオ 2: 地理的に分散された展開の一部のシナリオでは、強力な一貫性のあるフォロワー読み取りが使用されている場合、フォロワーから読み取られたデータがリーダーに格納されているデータと一致していることを確認するために、TiDB は検証のために異なるデータセンターから`Readindex`を要求します。クエリ プロセス全体のアクセス レイテンシが増加します。 Stale Read を使用すると、TiDB は現在のデータ センターのレプリカにアクセスして、リアルタイム パフォーマンスを犠牲にして対応するデータを読み取ります。これにより、クロスセンター接続によってもたらされるネットワーク レイテンシが回避され、クエリ全体のアクセス レイテンシが短縮されます。詳細については、 [3 つのデータ センター展開でのローカル読み取り](/best-practices/three-dc-local-read.md)を参照してください。

</CustomContent>

<CustomContent platform="tidb-cloud">

トランザクションに読み取り操作のみが含まれ、データの古さをある程度許容できる場合は、Stale Read を使用して履歴データを取得できます。 TiDB は Stale Read を使用して、リアルタイムのパフォーマンスをいくらか犠牲にしてクエリ要求を任意のレプリカに送信するため、クエリ実行のスループットが向上します。特に小さなテーブルがクエリされるいくつかのシナリオでは、強力な一貫性のある読み取りが使用されると、リーダーが特定のストレージ ノードに集中し、クエリのプレッシャーがそのノードにも集中する可能性があります。したがって、そのノードがクエリ全体のボトルネックになる可能性があります。ただし、古い読み取りは、クエリの全体的なスループットを向上させ、クエリのパフォーマンスを大幅に向上させることができます。

</CustomContent>

## 用途 {#usages}

TiDB は、次のように、ステートメント レベルおよびセッション レベルで Stale Read を実行するメソッドを提供します。

-   ステートメント レベル
    -   正確な時点の指定 (**推奨**): 分離レベルに違反することなく、特定の時点からグローバルに一貫性のあるデータを TiDB で読み取る必要がある場合は、クエリ ステートメントでその時点の対応するタイムスタンプを指定できます。詳細な使用方法については、 [`AS OF TIMESTAMP`句](/as-of-timestamp.md#syntax)を参照してください。
    -   時間範囲の指定: 分離レベルに違反することなく、時間範囲内でできるだけ新しいデータを TiDB で読み取る必要がある場合は、クエリ ステートメントで時間範囲を指定できます。指定された時間範囲内で、TiDB は適切なタイムスタンプを選択して、対応するデータを読み取ります。 「適切」とは、このタイムスタンプより前に開始され、アクセスされたレプリカでコミットされていないトランザクションがないことを意味します。つまり、TiDB はアクセスされたレプリカで読み取り操作を実行でき、読み取り操作はブロックされません。詳しい使い方は[`AS OF TIMESTAMP`句](/as-of-timestamp.md#syntax)と[`TIDB_BOUNDED_STALENESS`関数](/as-of-timestamp.md#syntax)の紹介を参照してください。
-   セッションレベル
    -   時間範囲の指定: セッションで、分離レベルに違反することなく、後続のクエリで時間範囲内で TiDB が可能な限り新しいデータを読み取る必要がある場合は、 `tidb_read_staleness`システム変数を設定して時間範囲を指定できます。詳しい使い方は[`tidb_read_staleness`](/tidb-read-staleness.md)を参照してください。