#### quick regression for pH potassium phosphate buffers
library(tidyverse)
library(scam)
library(here)

dir.create(here("output/tables/pH"), recursive = TRUE, showWarnings = FALSE)

pH_gradient <- read_csv(file = here("data/pH/potassium_phosphate_ph_buffers.csv"))

 

df_long <- pH_gradient |> pivot_longer(c(SolA, SolB), names_to = "solution", values_to = "ml")

ggplot(df_long, aes(pH, ml, color = solution)) +
  geom_point(size = 2) +
  # linear model lines; extend beyond observed range
  geom_smooth(method = "lm", se = FALSE, fullrange = TRUE) +
  scale_x_continuous(limits = c(5.0, 8.5)) +   # <- extrapolate view
  labs(x = "pH", y = "Volume (ml)", color = "Solution")


# df with columns: pH, SolA_ml, SolB_ml (sum ≈ 100)
stopifnot(all(abs(pH_gradient$SolA + pH_gradient$SolB - 100) < 1e-6))  # optional check


# Fit pH ~ log10(SolB/SolA)
df <- pH_gradient |>
  mutate(log_ratio = log10(SolB / SolA))

mod <- lm(pH ~ log_ratio, data = df)
summary(mod)

# Inverse function: pH -> (SolA, SolB) at total Vtot (default 100 ml)
mix_at_pH <- function(pH_target, Vtot = 100) {
  a <- coef(mod)[["(Intercept)"]]
  b <- coef(mod)[["log_ratio"]]
  r <- 10^((pH_target - a)/b)                # SolB/SolA
  SolB <- Vtot * r/(1 + r)
  SolA <- Vtot - SolB
  # clamp to physical limits just in case
  SolA <- pmax(pmin(SolA, Vtot), 0)
  SolB <- pmax(pmin(SolB, Vtot), 0)
  data.frame(pH = pH_target, SolA = SolA, SolB = SolB)
}

# Examples (your requested extremes)
mix_at_pH(c(3.2, 10.1))



new_pH <- seq(3.2, 10.1, by = 0.3)
pred <- do.call(rbind, lapply(new_pH, mix_at_pH))

obs_long <- tidyr::pivot_longer(pH_gradient, c(SolA, SolB),
                                names_to="Solution", values_to="ml")
pred_long <- tidyr::pivot_longer(pred, c(SolA, SolB),
                                 names_to="Solution", values_to="ml")

ggplot() +
  geom_point(data = obs_long, aes(pH, ml, color = Solution), size = 2) +
  geom_line(data = pred_long, aes(pH, ml, color = Solution), linetype = 2) +
  labs(x = "pH", y = "Volume (ml)", color = "Solution",
       title = "Observed points and log-ratio model extrapolation") +
  theme_minimal()



pred_wide <- pred_long |>
  pivot_wider(names_from = Solution, values_from = ml)




##now let's caclulate the ammounts we need to prepare 50ml of the adjuste pH media

pH_gradient <- pH_gradient |>
  mutate(SolA_50ml = SolA/4,
         SolB_50ml = SolB/4)

pred_wide <- pred_wide |>
  mutate(SolA_50ml = SolA/4,
         SolB_50ml = SolB/4)


write_csv(pH_gradient, file = here("output/tables/pH/pH_buffers.csv"), quote = NULL, col_names = T)
write_csv(pred_wide, file = here("output/tables/pH/pH_buffers_extended.csv"), quote = NULL, col_names = T)
