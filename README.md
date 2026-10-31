# db
Thiết kế DB mẫu để thực hiện các Demo
-----------------------------------------------------------------
## Hệ thống quản lý đơn hàng - Order Management
- Sử dụng ChatGPT + Mockaroo để dựng PostreSQL data ...
```declarative
Hay thiet ke DB (tables, fields, primary key, foreign key) cua 'Order Management System', bao gom cac tables sau day :
- customers (id, name (required), gender, birthday, active, created_at, updated_at)
- products(id, name (required), code (required), price (required), description, created_at, updated_at)
- orders(id,customer_id, ..., created_at, updated_at),
- order_items(id, order_id, product_id, ...., priority, quantity)
- inventories(id, product_id, quantity, inputted_at)
```

- Mockaroo script
```declarative
__rownum: Row Number (Hidden field)

name:
pad(__rownum, 4, "0", "left") + "-" + this

gender: 
if this == 'Male' then 'MALE'
elseif this == 'Female' then 'FEMALE'
else 'OTHER' end

active: 'true'
```
- 