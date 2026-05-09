# FoodChain Menu Seeder
# Calls menu-service directly on port 8082 - no JWT needed.

$BASE  = 'http://localhost:8082/api'
$HEADS = @{ 'Content-Type' = 'application/json'; 'X-User-Id' = 'seed-script'; 'X-User-Role' = 'OFFICE_ADMIN' }

function Post($url, $body) {
    try {
        Invoke-RestMethod -Method POST -Uri $url -Headers $HEADS -Body ($body | ConvertTo-Json -Depth 3)
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $null
    }
}

# ── 1. Categories ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host 'Creating categories...' -ForegroundColor Cyan

$cats = @(
    @{ name='Starters';           displayOrder=1 },
    @{ name='Burgers';            displayOrder=2 },
    @{ name='Grills and Mains';   displayOrder=3 },
    @{ name='Wraps and Sandwiches'; displayOrder=4 },
    @{ name='Sides';              displayOrder=5 },
    @{ name='Salads';             displayOrder=6 },
    @{ name='Desserts';           displayOrder=7 },
    @{ name='Drinks';             displayOrder=8 }
)

$catIds = @{}
foreach ($c in $cats) {
    $r = Post "$BASE/menu/categories" $c
    if ($r -and $r.id) {
        $catIds[$c.name] = $r.id
        Write-Host "  OK $($c.name) -> $($r.id)" -ForegroundColor Green
    }
}

# ── 2. Menu Items ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host 'Seeding menu items...' -ForegroundColor Cyan

$items = @(
    # Starters
    @{ name='Crispy Calamari';          description='Lightly battered calamari rings served with marinara dip and lemon wedges.';                     cat='Starters';           price=18.00 },
    @{ name='Loaded Nachos';            description='Tortilla chips piled with melted cheese, jalapenos, sour cream and guacamole.';                   cat='Starters';           price=22.00 },
    @{ name='Chicken Wings 6pcs';       description='Slow-marinated wings in your choice of BBQ, buffalo or honey-garlic sauce.';                      cat='Starters';           price=28.00 },
    @{ name='Garlic Cheese Bread';      description='Toasted sourdough brushed with garlic butter and topped with melted mozzarella.';                 cat='Starters';           price=14.00 },
    @{ name='Soup of the Day';          description='Chefs daily rotating soup served with warm crusty bread.';                                        cat='Starters';           price=16.00 },
    @{ name='Bruschetta Trio';          description='Grilled ciabatta with tomato-basil, mushroom and smoked salmon toppings.';                        cat='Starters';           price=20.00 },

    # Burgers
    @{ name='Classic Beef Burger';      description='100g house-ground beef patty, lettuce, tomato, pickles and our signature sauce in a brioche bun.'; cat='Burgers';           price=42.00 },
    @{ name='Double Smash Burger';      description='Two smashed beef patties, American cheese, caramelised onions and pickles.';                      cat='Burgers';            price=52.00 },
    @{ name='Crispy Chicken Burger';    description='Buttermilk-fried chicken thigh, slaw and sriracha mayo in a toasted bun.';                        cat='Burgers';            price=45.00 },
    @{ name='BBQ Bacon Burger';         description='Beef patty, crispy bacon, cheddar, BBQ sauce and tobacco onions.';                                cat='Burgers';            price=55.00 },
    @{ name='Mushroom Swiss Burger';    description='Grilled beef patty topped with sauteed mushrooms and melted Swiss cheese.';                       cat='Burgers';            price=48.00 },
    @{ name='Veggie Bean Burger';       description='Spiced black-bean patty, avocado, pickled red onion and chipotle mayo.';                          cat='Burgers';            price=38.00 },
    @{ name='Spicy Jalapeno Burger';    description='Double beef patty, pepper-jack cheese, fresh jalapenos and habanero ketchup.';                    cat='Burgers';            price=50.00 },
    @{ name='Fish Fillet Burger';       description='Panko-crusted cod fillet, tartare sauce, lettuce and tomato on a sesame bun.';                    cat='Burgers';            price=44.00 },

    # Grills and Mains
    @{ name='Grilled Chicken Breast';   description='Herb-marinated chicken breast served with roasted vegetables and lemon jus.';                     cat='Grills and Mains';   price=58.00 },
    @{ name='Ribeye Steak 300g';        description='Prime ribeye cooked to your liking, served with fries, grilled tomato and peppercorn sauce.';     cat='Grills and Mains';   price=120.00 },
    @{ name='Grilled Salmon';           description='Atlantic salmon fillet on a bed of sauteed spinach with dill cream sauce.';                       cat='Grills and Mains';   price=85.00 },
    @{ name='Mixed Grill Platter';      description='Chicken kebab, kofta, shish tawook and lamb chop served with rice and grilled bread.';            cat='Grills and Mains';   price=95.00 },
    @{ name='Lamb Chops';               description='Rosemary-rubbed lamb chops with chimichurri and roasted garlic mash.';                            cat='Grills and Mains';   price=110.00 },
    @{ name='Chicken Tikka Masala';     description='Tender chicken in a rich spiced tomato and cream sauce served with basmati rice.';                cat='Grills and Mains';   price=65.00 },
    @{ name='Beef Kofta Skewers';       description='Three spiced beef kofta skewers with fattoush salad and tahini.';                                 cat='Grills and Mains';   price=72.00 },
    @{ name='Grilled Halloumi Steak';   description='Thick-cut halloumi with watermelon-mint salsa and pomegranate molasses.';                         cat='Grills and Mains';   price=55.00 },

    # Wraps and Sandwiches
    @{ name='Chicken Shawarma Wrap';    description='Slow-roasted chicken, garlic sauce, pickles and chips wrapped in fresh saj bread.';               cat='Wraps and Sandwiches'; price=35.00 },
    @{ name='Club Sandwich';            description='Triple-decker with grilled chicken, bacon, egg, lettuce, tomato and mayo.';                       cat='Wraps and Sandwiches'; price=38.00 },
    @{ name='Falafel Wrap';             description='Crispy falafel, hummus, tabbouleh and tahini in a warm flatbread.';                               cat='Wraps and Sandwiches'; price=30.00 },
    @{ name='Caesar Chicken Wrap';      description='Grilled chicken, romaine, parmesan and Caesar dressing in a flour tortilla.';                     cat='Wraps and Sandwiches'; price=40.00 },
    @{ name='BLT Baguette';             description='Crispy bacon, vine tomatoes, baby gem lettuce and smoked mayo in a toasted baguette.';             cat='Wraps and Sandwiches'; price=32.00 },
    @{ name='Philly Cheesesteak';       description='Shaved ribeye, grilled onions, peppers and provolone in a hoagie roll.';                          cat='Wraps and Sandwiches'; price=45.00 },

    # Sides
    @{ name='Loaded Fries';             description='Crispy fries topped with cheese sauce, bacon bits and spring onion.';                             cat='Sides';              price=22.00 },
    @{ name='Sweet Potato Fries';       description='Seasoned sweet potato fries served with chipotle dipping sauce.';                                 cat='Sides';              price=24.00 },
    @{ name='Onion Rings';              description='Beer-battered golden onion rings with ranch dip.';                                                 cat='Sides';              price=20.00 },
    @{ name='Coleslaw';                 description='Creamy homemade coleslaw with a hint of apple cider vinegar.';                                    cat='Sides';              price=14.00 },
    @{ name='Corn on the Cob';          description='Grilled sweet corn with herb butter and smoked paprika.';                                         cat='Sides';              price=16.00 },
    @{ name='Mac and Cheese';           description='Slow-baked macaroni in a four-cheese sauce with a golden breadcrumb crust.';                      cat='Sides';              price=28.00 },
    @{ name='Mashed Potato';            description='Buttery smooth mashed potatoes with chives and cream.';                                           cat='Sides';              price=18.00 },

    # Salads
    @{ name='Caesar Salad';             description='Romaine, croutons, shaved parmesan and house Caesar dressing.';                                   cat='Salads';             price=32.00 },
    @{ name='Greek Salad';              description='Cucumber, tomato, olives, red onion, feta and oregano with olive oil dressing.';                  cat='Salads';             price=28.00 },
    @{ name='Fattoush Salad';           description='Lebanese bread salad with seasonal vegetables, sumac and pomegranate dressing.';                  cat='Salads';             price=26.00 },
    @{ name='Quinoa Avocado Bowl';      description='Tri-colour quinoa, avocado, edamame, cucumber and sesame-ginger dressing.';                       cat='Salads';             price=38.00 },
    @{ name='Garden Fresh Salad';       description='Mixed greens, cherry tomatoes, radish and house vinaigrette.';                                    cat='Salads';             price=22.00 },

    # Desserts
    @{ name='Chocolate Lava Cake';      description='Warm dark-chocolate fondant with a molten centre, served with vanilla ice cream.';                cat='Desserts';           price=28.00 },
    @{ name='Cheesecake of the Day';    description='Ask your server for todays flavour - always made fresh in-house.';                                cat='Desserts';           price=30.00 },
    @{ name='Tiramisu';                 description='Classic Italian mascarpone and espresso-soaked ladyfinger dessert.';                              cat='Desserts';           price=32.00 },
    @{ name='Creme Brulee';             description='Silky vanilla custard with a caramelised sugar crust, served with fresh berries.';                cat='Desserts';           price=26.00 },
    @{ name='Ice Cream 3 Scoops';       description='Choice of vanilla, chocolate, strawberry, pistachio or salted caramel.';                         cat='Desserts';           price=24.00 },
    @{ name='Kunafa';                   description='Shredded filo pastry with sweet cheese filling, rose water syrup and pistachios.';                cat='Desserts';           price=28.00 },

    # Drinks
    @{ name='Fresh Lemonade';           description='Freshly squeezed lemonade with mint and a hint of rose water. Still or sparkling.';               cat='Drinks';             price=18.00 },
    @{ name='Mango Smoothie';           description='Blended Alphonso mango with coconut milk and a squeeze of lime.';                                 cat='Drinks';             price=22.00 },
    @{ name='Iced Coffee';              description='Cold-brew coffee over ice with your choice of milk and a drizzle of caramel.';                    cat='Drinks';             price=20.00 },
    @{ name='Mineral Water 500ml';      description='Still or sparkling mineral water.';                                                               cat='Drinks';             price=8.00  },
    @{ name='Fresh Orange Juice';       description='Pressed to order from Valencia oranges.';                                                         cat='Drinks';             price=24.00 },
    @{ name='Soft Drink Can';           description='Pepsi, Diet Pepsi, 7Up or Mountain Dew - your choice.';                                           cat='Drinks';             price=12.00 },
    @{ name='Arabic Coffee';            description='Traditional cardamom-spiced qahwa served with dates.';                                            cat='Drinks';             price=14.00 },
    @{ name='Watermelon Juice';         description='Cold-pressed watermelon juice with a pinch of sea salt and fresh mint.';                          cat='Drinks';             price=20.00 }
)

$created = 0
$failed  = 0

foreach ($item in $items) {
    $catId = $catIds[$item.cat]
    if (-not $catId) {
        Write-Host "  SKIP $($item.name) - category not found" -ForegroundColor Yellow
        $failed++
        continue
    }
    $payload = @{
        name        = $item.name
        description = $item.description
        categoryId  = $catId
        basePrice   = $item.price
    }
    $r = Post "$BASE/menu/items" $payload
    if ($r -and $r.id) {
        Write-Host "  OK $($item.name)" -ForegroundColor Green
        $created++
    } else {
        $failed++
    }
}

Write-Host ''
Write-Host "Done. $created items created, $failed failed." -ForegroundColor Cyan
