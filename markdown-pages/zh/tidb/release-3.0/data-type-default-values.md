---
title: 数据类型的默认值
aliases: ['/docs-cn/v3.0/data-type-default-values/','/docs-cn/v3.0/reference/sql/data-types/default-values/']
---

# 数据类型的默认值

在一个数据类型描述中的 `DEFAULT value` 段描述了一个列的默认值。这个默认值必须是常量，不可以是一个函数或者是表达式。但是对于时间类型，可以例外的使用 `NOW`、`CURRENT_TIMESTAMP`、`LOCALTIME`、`LOCALTIMESTAMP` 等函数作为 `DATETIME` 或者 `TIMESTAMP` 的默认值。

`BLOB`、`TEXT` 以及 `JSON` 不可以设置默认值。

如果一个列的定义中没有 `DEFAULT` 的设置。TiDB 按照如下的规则决定:

* 如果该类型可以使用 `NULL` 作为值，那么这个列会在定义时添加隐式的默认值设置 `DEFAULT NULL`。
* 如果该类型无法使用 `NULL` 作为值，那么这个列在定义时不会添加隐式的默认值设置。

对于一个设置了 `NOT NULL` 但是没有显式设置 `DEFAULT` 的列，当 `INSERT`、`REPLACE` 没有涉及到该列的值时，TiDB 根据当时的 `SQL_MODE` 进行不同的行为：

* 如果此时是 `strict sql mode`，在事务中的语句会导致事务失败并回滚，非事务中的语句会直接报错。
* 如果此时不是 `strict sql mode`，TiDB 会为这列赋值为列数据类型的隐式默认值。

此时隐式默认值的设置按照如下规则：

* 对于数值类型，它们的默认值是 0。当有 `AUTO_INCREMENT` 参数时，默认值会按照增量情况赋予正确的值。
* 对于除了时间戳外的日期时间类型，默认值会是该类型的“零值”。时间戳类型的默认值会是当前的时间。
* 对于除枚举以外的字符串类型，默认值会是空字符串。对于枚举类型，默认值是枚举中的第一个值。