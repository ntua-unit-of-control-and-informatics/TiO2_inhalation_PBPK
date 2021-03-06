library(deSolve) 
library(ggplot2)
library(rstan)

# ALL files should be in the same working directory. The user should set this directory under the 'path' varialbe
options(max.print=999999)
path <- "" ###### USER INPUT HERE #####
setwd(path)
load("results.RData")
stan_fit <- extract(fit)

# !!!!!!!!!  In exposure concentration, the last value will not be taken into account by the model, so it better be zero !!!!!!!!!!!!!!!!!!!
##########################################
# Function for creating parameter vector #
##########################################

create.params <- function(input, stan_fit, stochastic = TRUE){
  with( as.list(input),{
    
    # List with names of all possible compartments
    comps <- list("Lungs" = "Lungs" ,"Liver"="Liver", "Spleen"="Spleen", "Kidneys"="Kidneys", "Heart"="Heart",  "Brain"="Brain",
                  "Uterus"="Uterus", "Skeleton"="Skeleton", "Skin"="Skin", "Soft"="Soft") # List with names of all possible compartments
    
    
    
    ### Density of tissues/organs
    d_tissue <- 1 #g/ml
    d_skeleton <- 1.92 #g/ml
    d_adipose <- 0.940 #g/ml
    
    Q_total <- (1.54*weight^0.75)*60 # Total Cardiac Output (ml/h)
    
    Total_Blood <- 0.06*weight+0.77 # Total blood volume (ml)
    
    #Arterial blood volume
    Vart <- 0.15*Total_Blood #(ml)
    
    #Veins blood volume
    Vven <-0.64*Total_Blood #(ml)
    
    #Tissue weight fraction 
    Tissue_fractions <- c(0.5, 3.66, 0.2, 0.73, 0.33, 0.57, 0.011, 10, 19.03, NA)/100 # % of BW. Na values refers to the volume of the rest organs(RoB)
    
    #Regional blood flow fraction
    Regional_flow_fractions <- c(100, 17.4, 1.22, 14.1, 4.9, 2, 1.1, 12.2, 5.8, NA)/100 # % of total cardiac output
    
    #Capillary volume fractions (fractions of tissue volume)
    Capillary_fractions <- c(0.36, 0.21, 0.22, 0.16, 0.26, 0.03, 0.04, 0.04, 0.02, 0.04) # fraction of tissue volume
    # Where NA, it is the same value as Rest of Body due to luck od data for uterus and adipose
    
    #Macrophage content (g per gram of tissue)
    Macrophage_fraction <- c(0.04, 0.1, 0.3, 0.02, 0.02, 0.04, 0.04, 0.04, 0.02, 0.02) 
    Macrophage_fraction_blood <- 0.01
    
    CLE_ua <- 0
    CLE_muc <-  0.01181567
    k_ua_br <- 0
    CLE_hep <-  1.52e-03
    CLE_muc_cor <- 1
    k_ab0 <- 1.45
    k_de <- 6.7e-19
    k_ab0_spl <- 0.5
    
    W_tis <- rep(0,length(comps))
    V_tis <- rep(0,length(comps))
    V_cap <- rep(0,length(comps))
    W_macro <- rep(0,length(comps)) 
    Q <- rep(0,length(comps))
    
    for (i in 1:(length(comps)-1)) {
      control <- comps[i]
      
      Tissue_fractions[i] <- ifelse(is.na(control), NA, Tissue_fractions[i])
      Regional_flow_fractions[i] <- ifelse(is.na(control), NA, Regional_flow_fractions[i])
      Capillary_fractions[i] <- ifelse(is.na(control), NA, Capillary_fractions[i])
      Macrophage_fraction[i] <- ifelse(is.na(control), NA, Macrophage_fraction[i])
      
      ### Calculation of tissue weights  
      W_tis[i] <- weight*Tissue_fractions[i]
      W_macro[i] <- W_tis[i]*Macrophage_fraction[i]
      
      ###Calculation of tissue volumes
      
      if (i==9){
        V_tis[i] <- W_tis[i]/d_skeleton
      } else{
        V_tis[i] <- W_tis[i]/d_tissue 
      }
      
      ###Calculation of capillary volumes
      V_cap[i] <- V_tis[i]*Capillary_fractions[i]
      
      
      ###Calculation of regional blood flows
      Q[i] <- Q_total*Regional_flow_fractions[i]
    }
    
    ### Calculations for "Rest of Body" compartment
    W_tis[10] <- weight - sum(W_tis[1:(length(W_tis)-1)], na.rm = TRUE)
    V_tis[10] <- W_tis[10]/d_adipose     #(considering that the density of the rest tissues is 1 g/ml)
    Q[10] <- Q_total - sum(Q[2:(length(Q)-1)],na.rm = TRUE)
    V_cap[10] <- V_tis[10]*Capillary_fractions[10]
    # V_cap[9] <- Total_Blood - Vven - Vart - sum(V_cap[1:(length(V_cap)-1)], na.rm = TRUE) #this is problematic because it produces negative number
    W_macro[10] <- W_tis[10]*Macrophage_fraction[10]
    #Capillary_fractions[1] <- V_cap[1]/V_tis[1]
    
    Macro_blood <- Macrophage_fraction_blood*Total_Blood
    Wm_al <-  W_macro[1]
    
    if(stochastic == TRUE){
            x_fast <- exp(rnorm(1,mean(stan_fit$theta_tr[,1]), sd(stan_fit$theta_tr[,1])))
            CLE_ur<-  exp(rnorm(1,mean(stan_fit$theta_tr[,2]), sd(stan_fit$theta_tr[,2])))
            uptake <- exp(rnorm(1,mean(stan_fit$theta_tr[,3]), sd(stan_fit$theta_tr[,3])))
            k_alpc_tb <- exp(rnorm(1,mean(stan_fit$theta_tr[,4]), sd(stan_fit$theta_tr[,4])))
            k_lu_al <-  exp(rnorm(1,mean(stan_fit$theta_tr[,5]), sd(stan_fit$theta_tr[,5])))
            k_al_lu <- exp(rnorm(1,mean(stan_fit$theta_tr[,6]), sd(stan_fit$theta_tr[,6])))
            uptake_al <- exp(rnorm(1,mean(stan_fit$theta_tr[,7]), sd(stan_fit$theta_tr[,7])))
            uptake_skel <- exp(rnorm(1,mean(stan_fit$theta_tr[,8]), sd(stan_fit$theta_tr[,8])))
            P_lu <- exp(rnorm(1,mean(stan_fit$theta_tr[,9]), sd(stan_fit$theta_tr[,9])))
            P_ki <- exp(rnorm(1,mean(stan_fit$theta_tr[,10]), sd(stan_fit$theta_tr[,10])))
            P_br <- exp(rnorm(1,mean(stan_fit$theta_tr[,11]), sd(stan_fit$theta_tr[,11])))
            P_ut <- exp(rnorm(1,mean(stan_fit$theta_tr[,12]), sd(stan_fit$theta_tr[,12])))
            P_skin <- exp(rnorm(1,mean(stan_fit$theta_tr[,13]), sd(stan_fit$theta_tr[,13])))
            P_soft_skel_ht <- exp(rnorm(1,mean(stan_fit$theta_tr[,14]), sd(stan_fit$theta_tr[,14])))
            P_li_spl <- exp(rnorm(1,mean(stan_fit$theta_tr[,15]), sd(stan_fit$theta_tr[,15])))
            
    }else{
      x_fast <- exp(mean(stan_fit$theta_tr[,1]))
      CLE_ur<-  exp(mean(stan_fit$theta_tr[,2]))
      uptake <- exp(mean(stan_fit$theta_tr[,3]))
      k_alpc_tb <- exp(mean(stan_fit$theta_tr[,4]))
      k_lu_al <-  exp(mean(stan_fit$theta_tr[,5]))
      k_al_lu <- exp(mean(stan_fit$theta_tr[,6]))
      uptake_al <- exp(mean(stan_fit$theta_tr[,7]))
      uptake_skel <- exp(mean(stan_fit$theta_tr[,8]))
      P_lu <- exp(mean(stan_fit$theta_tr[,9]))
      P_ki <- exp(mean(stan_fit$theta_tr[,10]))
      P_br <- exp(mean(stan_fit$theta_tr[,11]))
      P_ut <- exp(mean(stan_fit$theta_tr[,12]))
      P_skin <- exp(mean(stan_fit$theta_tr[,13]))
      P_soft_skel_ht <- exp(mean(stan_fit$theta_tr[,14]))
      P_li_spl <- exp(mean(stan_fit$theta_tr[,15]))
      
    }

    
    e1 <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean =  mean(stan_fit$sigma[,1]) , sd =  sd(stan_fit$sigma[,1]))
    e2 <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean =  mean(stan_fit$sigma[,2]) , sd =  sd(stan_fit$sigma[,2]))
    e3 <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean =  mean(stan_fit$sigma[,3]) , sd =  sd(stan_fit$sigma[,3]))
    
    uptake_spl <- uptake
    P_li <- P_li_spl
    P_spl <- P_li_spl
    P_ht <- P_soft_skel_ht
    P_soft <- P_soft_skel_ht
    P_skel <- P_soft_skel_ht
    
    x_lu <- x_fast
    x_li <- x_fast
    x_spl <- x_fast
    x_ki <- x_fast
    x_ht <- x_fast
    x_br <- x_fast
    x_ut <- x_fast
    x_skel <- x_fast
    x_skin <- x_fast
    x_soft <- x_fast
    
    return(list("Vlu_tis"= V_tis[1], "Vli_tis"= V_tis[2], "Vspl_tis"= V_tis[3], "Vki_tis"= V_tis[4],"Vht_tis"= V_tis[5],
                "Vbr_tis"= V_tis[6], "Vut_tis"= V_tis[7], "Vskel_tis"= V_tis[8], "Vskin_tis"= V_tis[9], "Vsoft_tis"= V_tis[10],
                "Vven"=Vven, "Vart"=Vart, "V_blood"=Total_Blood,
                
                "Vlu_cap"= V_cap[1], "Vli_cap"= V_cap[2], "Vspl_cap"= V_cap[3], "Vki_cap"= V_cap[4], "Vht_cap"= V_cap[5],
                "Vbr_cap"= V_cap[6], "Vut_cap"= V_cap[7], "Vskel_cap"= V_cap[8], "Vskin_cap"= V_cap[9], "Vsoft_cap"= V_cap[10],
                
                "Q_lu"= Q[1], "Q_li"= Q[2], "Q_spl"= Q[3], "Q_ki"= Q[4], "Q_ht"= Q[5], "Q_br"= Q[6], "Q_ut"= Q[7], "Q_skel"= Q[8],
                "Q_skin"= Q[9], "Q_soft"= Q[10],  "Q_total"=Q_total, 
                
                "Wm_blood" = Macro_blood, "Wm_lu"= W_macro[1], "Wm_li"= W_macro[2], "Wm_spl"= W_macro[3], "Wm_ki"= W_macro[4], 
                "Wm_ht"= W_macro[5], "Wm_br"= W_macro[6], "Wm_ut"= W_macro[7], "Wm_skel"= W_macro[8], "Wm_skin"= W_macro[9],
                "Wm_soft"= W_macro[10],
                
                "Inhaled.vol.rate" = Inhaled.vol.rate, "dep.ua" = dep.ua, "dep.tb" = dep.tb, "dep.al" = dep.al, 
                "exposure.concentration" = exposure.concentration, "exposure.time" = exposure.time,
                
                "CLE_ua" = CLE_ua, "CLE_muc" = CLE_muc,
                "x_fast" = x_fast ,   "CLE_ur" = CLE_ur, "CLE_hep" = CLE_hep, 
                "CLE_muc_cor" = CLE_muc_cor, "k_ab0" = k_ab0, "k_de" = k_de,
                "k_ab0_spl" = k_ab0_spl, "uptake" = uptake,
                "Wm_al" = Wm_al, "k_ua_br" = k_ua_br, "k_alpc_tb" = k_alpc_tb, "k_lu_al" = k_lu_al,
                "k_al_lu" = k_al_lu,   "uptake_al" =uptake_al, 
                "uptake_skel" = uptake_skel, "uptake_spl" = uptake_spl,
                
                "P_lu"= P_lu, "x_lu" = x_lu, "P_li" = P_li, "x_li" = x_li, "P_spl" =P_spl, 
                "x_spl" = x_spl, "P_ki" = P_ki, "x_ki" = x_ki, "P_ht" = P_ht, "x_ht" = x_ht,
                "P_br" = P_br, "x_br" = x_br, "P_ut" = P_ut, x_ut = x_ut,
                "P_skel" = P_skel, "x_skel" = x_skel, "P_skin" = P_skin, "x_skin" = x_skin,
                "P_soft" = P_soft, "x_soft" = x_soft,
                
                "error1" = e1, "error2" = e2, "error3" = e3
    ))
    
  }) 
}


### store them once


#################################################
# Function for creating initial values for ODEs #
#################################################

create.inits <- function(parameters){
  with( as.list(parameters),{
    Mua<- 0; Mtb <- 0;Mal <- 0; Mal_pc <- 0; Mlu_cap <- 0;
    Mlu_tis <- 0; Mlu_pc <- 0; Mli_cap <- 0; Mli_tis <- 0;
    Mli_pc <- 0; Mspl_cap <- 0; Mspl_tis <- 0; Mspl_pc <- 0;
    Mki_cap <- 0; Mki_tis <- 0; Mki_pc <- 0; Mht_cap <- 0;
    Mht_tis <- 0; Mht_pc <- 0; Mbr_cap <- 0; Mbr_tis <- 0;
    Mbr_pc <- 0; Mut_cap <- 0; Mut_tis <- 0; Mut_pc <- 0;
    Mskel_cap <- 0; Mskel_tis <- 0; Mskel_pc <- 0; Mskin_cap <- 0;
    Mskin_tis <- 0; Mskin_pc <- 0; Msoft_cap <- 0; Msoft_tis <- 0;
    Msoft_pc <- 0; Art_blood <- 0; Ven_blood <- 0; Mblood_pc <- 0;
    Mfeces <- 0; Murine <- 0;
    
    return(c("Mua" = Mua, "Mtb" = Mtb, "Mal" = Mal,"Mal_pc" = Mal_pc,
             "Mlu_cap" = Mlu_cap, "Mlu_tis" = Mlu_tis, "Mlu_pc" = Mlu_pc, "Mli_cap" = Mli_cap, 
             "Mli_tis" = Mli_tis, "Mli_pc" = Mli_pc, "Mspl_cap" = Mspl_cap, "Mspl_tis" = Mspl_tis,
             "Mspl_pc" = Mspl_pc, "Mki_cap" = Mki_cap, "Mki_tis" = Mki_tis, "Mki_pc" = Mki_pc,
             "Mht_cap" = Mht_cap, "Mht_tis" = Mht_tis, "Mht_pc" = Mht_pc, "Mbr_cap" = Mbr_cap,
             "Mbr_tis" = Mbr_tis, "Mbr_pc" = Mbr_pc,  "Mut_cap" = Mut_cap, "Mut_tis" = Mut_tis,
             "Mut_pc" = Mut_pc, "Mskel_cap" = Mskel_cap, "Mskel_tis" = Mskel_tis, "Mskel_pc" = Mskel_pc, 
             "Mskin_cap" = Mskin_cap, "Mskin_tis" = Mskin_tis, "Mskin_pc" = Mskin_pc, "Msoft_cap" = Msoft_cap,
             "Msoft_tis" = Msoft_tis, "Msoft_pc" = Msoft_pc, "Art_blood" = Art_blood, "Ven_blood" = Ven_blood,
             "Mblood_pc" = Mblood_pc, "Mfeces" = Mfeces, "Murine" =Murine))
  }) 
}

#################################################
# Function for creating events #
#################################################
create.events<- function(parameters){
  with( as.list(parameters),{
    
    exposure.time <- seq(from=0, to=exposure.time , by=exposure.time /100) #inhalation time in hours (When was this applies)
    exposure.concentration <- rep(exposure.concentration,length(exposure.time))  # in mg/m^3
    
    
    lexposure <- length(exposure.concentration)
    ltimes <- length(exposure.time)
    
    add.tb <- rep(0,lexposure-1)
    add.al <- rep(0,lexposure-1)
    cur.time <- exposure.time[1]
    
    for (i in 1:(ltimes-1)){
      # Calculate the interval of exposure
      interval <- exposure.time[i+1] - cur.time
      add.tb[i] = interval * exposure.concentration[i] * (Inhaled.vol.rate/1000) * dep.tb * 1000 # deposited mass in microgram in trancheobronchial region
      add.al[i] = interval * exposure.concentration[i] * (Inhaled.vol.rate/1000) * dep.al * 1000 # deposited mass in microgram in alveolar region
      cur.time <- exposure.time[i+1]
    }
    
    if (lexposure == ltimes){
      events <- list(data = rbind(data.frame(var = "Mtb",  time = exposure.time[2:ltimes], 
                                             value = add.tb, method = c("add")),
                                  data.frame(var = "Mal",  time = exposure.time[2:ltimes], 
                                             value = add.al, method = c("add"))
                                  
                                  
      ))
    }else{
      stop("The user must provide t")
    }
    
    
    return(events)
  }) 
}


###################
# Custom function #
###################

custom.func <- function(){
  return()
}

#################
# ODEs system #
#################


ode.func <- function(time, Initial.values, Parameters, custom.func){
  with( as.list(c(Initial.values, Parameters)),{
    
    # concentrations in tissues
    #C_lu <- Lu_tissue/W_lu
    Clu_tis  <-  Mlu_tis/Vlu_tis
    Clu_cap <-  Mlu_cap/Vlu_cap
    Cli_tis  <-  Mli_tis/Vli_tis
    Cli_cap <-  Mli_cap/Vli_cap
    Cspl_tis  <-  Mspl_tis/Vspl_tis
    Cspl_cap  <-  Mspl_cap/Vspl_cap
    Cki_tis  <-  Mki_tis/Vki_tis
    Cki_cap  <-  Mki_cap/Vki_cap
    Cht_tis  <-  Mht_tis/Vht_tis
    Cht_cap  <-  Mht_cap/Vht_cap
    Cbr_tis  <-  Mbr_tis/Vbr_tis
    Cbr_cap  <-  Mbr_cap/Vbr_cap
    Cut_tis  <-  Mut_tis/Vut_tis
    Cut_cap  <-  Mut_cap/Vut_cap
    Cskel_tis  <-  Mskel_tis/Vskel_tis
    Cskel_cap  <-  Mskel_cap/Vskel_cap
    Cskin_tis  <-  Mskin_tis/Vskin_tis
    Cskin_cap  <-  Mskin_cap/Vskin_cap
    Csoft_tis  <-  Msoft_tis/Vsoft_tis
    Csoft_cap  <-  Msoft_cap/Vsoft_cap
    
    Cart <- Art_blood/(0.19*V_blood)
    Cven <- Ven_blood/(0.81*V_blood)
    
    # Uptake rates by phagocytizing cells
    kluab <- k_ab0*(1-(Mlu_pc/(Wm_lu*uptake)))
    kliab <- k_ab0*(1-(Mli_pc/(Wm_li*uptake)))
    ksplab <- k_ab0_spl*(1-(Mspl_pc/(Wm_spl*uptake_spl)))
    kkiab <- k_ab0*(1-(Mki_pc/(Wm_ki*uptake)))
    khtab <- k_ab0*(1-(Mht_pc/(Wm_ht*uptake)))
    kbrab <- k_ab0*(1-(Mbr_pc/(Wm_br*uptake)))
    kutab <- k_ab0*(1-(Mut_pc/(Wm_ut*uptake)))
    kskelab <- k_ab0*(1-(Mskel_pc/(Wm_skel*uptake_skel)))
    kskinab <- k_ab0*(1-(Mskin_pc/(Wm_skin*uptake)))
    ksoftab <- k_ab0*(1-(Msoft_pc/(Wm_soft*uptake)))
    kbloodab <- k_ab0*(1-(Mblood_pc/(Wm_blood*uptake)))
    kalab <- k_ab0*(1-(Mal_pc/(Wm_al*uptake_al)))
    
    #Upper airways
    dMua = -(k_ua_br*Mua) - (CLE_ua * Mua) 
    
    #Trancheobronchial region
    dMtb = (k_alpc_tb * Mal_pc) - (CLE_muc * CLE_muc_cor* Mtb) 
    
    #Alveolar region
    dMal = (k_lu_al * Mlu_tis) - (k_al_lu * Mal) - (Mal*kalab - Mal_pc*k_de)
    dMal_pc = (Mal*kalab - Mal_pc*k_de) - (k_alpc_tb * Mal_pc)
    
    #Lungs
    dMlu_cap  =  (Cven*Q_lu)- (Clu_cap*Q_lu) + (x_lu*Q_lu)*Clu_tis/P_lu - (x_lu*Q_lu)*Clu_cap ; 
    dMlu_tis  =  - (x_lu*Q_lu)*Clu_tis/P_lu + (x_lu*Q_lu)*Clu_cap - (Vlu_tis*Clu_tis*kluab - Mlu_pc*k_de) -
      (k_lu_al * Mlu_tis) + (k_al_lu * Mal) ; #Lung interstitium
    dMlu_pc  = (Vlu_tis*Clu_tis*kluab - Mlu_pc*k_de); 
    
    
    #Liver
    dMli_cap  = (Cart*Q_li) + (Cspl_cap*Q_spl) - (Cli_cap*(Q_li+Q_spl)) + (x_li*Q_li)*Cli_tis/P_li - (x_li*Q_li)*Cli_cap;  #capillary
    dMli_tis = - (x_li*Q_li)*Cli_tis/P_li + (x_li*Q_li)*Cli_cap -(Vli_tis*Cli_tis*kliab - Mli_pc*k_de) - (CLE_hep*Mli_tis) ; #tissue
    dMli_pc  = (Vli_tis*Cli_tis*kliab - Mli_pc*k_de) ; #Phagocytized
    
    
    #Spleen
    dMspl_cap  = (Cart*Q_spl) - (Cspl_cap*Q_spl) +  (x_spl*Q_spl)*Cspl_tis/P_spl - (x_spl*Q_spl)*Cspl_cap ;  #capillary
    dMspl_tis =  - (x_spl*Q_spl)*Cspl_tis/P_spl + (x_spl*Q_spl)*Cspl_cap - (Vspl_tis*Cspl_tis*ksplab - Mspl_pc*k_de)  ; #tissue
    dMspl_pc  = (Vspl_tis*Cspl_tis*ksplab - Mspl_pc*k_de) ; #seq
    
    
    #Kidneys
    dMki_cap  = (Cart*Q_ki) - (Cki_cap*Q_ki) +  (x_ki*Q_ki)*Cki_tis/P_ki - (x_ki*Q_ki)*Cki_cap- (CLE_ur*Mki_cap) ;  #capillary
    dMki_tis =  - (x_ki*Q_ki)*Cki_tis/P_ki + (x_ki*Q_ki)*Cki_cap - (Vki_tis*Cki_tis*kkiab - Mki_pc*k_de)  ; #tissue
    dMki_pc  = (Vki_tis*Cki_tis*kkiab - Mki_pc*k_de) ; #seq
    
    #Heart
    dMht_cap  = (Cart*Q_ht) - (Cht_cap*Q_ht) +  (x_ht*Q_ht)*Cht_tis/P_ht - (x_ht*Q_ht)*Cht_cap ;  #capillary
    dMht_tis =  - (x_ht*Q_ht)*Cht_tis/P_ht + (x_ht*Q_ht)*Cht_cap - (Vht_tis*Cht_tis*khtab - Mht_pc*k_de)  ; #tissue
    dMht_pc  = (Vht_tis*Cht_tis*khtab - Mht_pc*k_de) ; #seq
    
    
    #Brain
    dMbr_cap  = (Cart*Q_br) - (Cbr_cap*Q_br) +  (x_br*Q_br)*Cbr_tis/P_br - (x_br*Q_br)*Cbr_cap ;  #capillary
    dMbr_tis =  - (x_br*Q_br)*Cbr_tis/P_br + (x_br*Q_br)*Cbr_cap - (Vbr_tis*Cbr_tis*kbrab - Mbr_pc*k_de) + (k_ua_br*Mua)  ; #tissue
    dMbr_pc  =  (Vbr_tis*Cbr_tis*kbrab - Mbr_pc*k_de) ; #seq
    
    
    #Uterus
    dMut_cap  = (Cart*Q_ut) - (Cut_cap*Q_ut) +  (x_ut*Q_ut)*Cut_tis/P_ut - (x_ut*Q_ut)*Cut_cap ;  #capillary
    dMut_tis =  - (x_ut*Q_ut)*Cut_tis/P_ut + (x_ut*Q_ut)*Cut_cap - (Vut_tis*Cut_tis*kutab - Mut_pc*k_de)  ; #tissue
    dMut_pc  = (Vut_tis*Cut_tis*kutab - Mut_pc*k_de) ; #seq
    
    
    #Skeleton
    dMskel_cap  = (Cart*Q_skel) - (Cskel_cap*Q_skel) +  (x_skel*Q_skel)*Cskel_tis/P_skel - (x_skel*Q_skel)*Cskel_cap ;  #capillary
    dMskel_tis =  - (x_skel*Q_skel)*Cskel_tis/P_skel + (x_skel*Q_skel)*Cskel_cap - (Vskel_tis*Cskel_tis*kskelab - Mskel_pc*k_de)  ; #tissue
    dMskel_pc  = (Vskel_tis*Cskel_tis*kskelab - Mskel_pc*k_de) ; #seq
    
    #Skin
    dMskin_cap  = (Cart*Q_skin) - (Cskin_cap*Q_skin) +  (x_skin*Q_skin)*Cskin_tis/P_skin - (x_skin*Q_skin)*Cskin_cap ;  #capillary
    dMskin_tis =  - (x_skin*Q_skin)*Cskin_tis/P_skin + (x_skin*Q_skin)*Cskin_cap - (Vskin_tis*Cskin_tis*kskinab - Mskin_pc*k_de)  ; #tissue
    dMskin_pc  = (Vskin_tis*Cskin_tis*kskinab - Mskin_pc*k_de) ; #seq
    
    #Soft
    dMsoft_cap  = (Cart*Q_soft) - (Csoft_cap*Q_soft) +  (x_soft*Q_soft)*Csoft_tis/P_soft - (x_soft*Q_soft)*Csoft_cap ;  #capillary
    dMsoft_tis =  - (x_soft*Q_soft)*Csoft_tis/P_soft + (x_soft*Q_soft)*Csoft_cap - (Vsoft_tis*Csoft_tis*ksoftab - Msoft_pc*k_de)  ; #tissue
    dMsoft_pc  = (Vsoft_tis*Csoft_tis*ksoftab - Msoft_pc*k_de) ; #seq
    
    
    #Blood
    dArt_blood = (Clu_cap*Q_lu) - Cart* (Q_li + Q_spl+ Q_ki + Q_ht + Q_br + Q_ut + Q_skel + Q_skin + Q_soft) -  
      (0.19*V_blood*Cart*kbloodab - 0.19* Mblood_pc*k_de); 
    dVen_blood = (Cli_cap*(Q_li+Q_spl)) +  (Cki_cap*Q_ki) + (Cht_cap*Q_ht) + (Cbr_cap*Q_br) + (Cut_cap*Q_ut) + (Cskel_cap*Q_skel) +
      (Cskin_cap*Q_skin) + (Csoft_cap*Q_soft) - (Cven*Q_lu)  -  (0.81*V_blood*Cven*kbloodab - 0.81* Mblood_pc*k_de)
    dMblood_pc <- ((0.19*V_blood*Cart + 0.81*V_blood*Cven)*kbloodab - Mblood_pc*k_de) 
    
    #Feces
    dMfeces = (CLE_hep*Mli_tis) + (CLE_ua * Mua) + (CLE_muc* CLE_muc_cor * Mtb)  ;
    
    #Urine
    dMurine = (CLE_ur*Mki_cap) ;
    
    Total_lungs <- Mal + Mal_pc + Mlu_cap + Mlu_tis + Mlu_pc + Mtb 
    
    
    
    list(c(dMua = dMua, dMtb = dMtb, dMal = dMal,dMal_pc = dMal_pc,
           dMlu_cap = dMlu_cap, dMlu_tis = dMlu_tis, dMlu_pc = dMlu_pc, dMli_cap = dMli_cap, 
           dMli_tis = dMli_tis, dMli_pc = dMli_pc, dMspl_cap = dMspl_cap, dMspl_tis = dMspl_tis,
           dMspl_pc = dMspl_pc, dMki_cap = dMki_cap, dMki_tis = dMki_tis, dMki_pc = dMki_pc,
           dMht_cap = dMht_cap, dMht_tis = dMht_tis, dMht_pc = dMht_pc, dMbr_cap = dMbr_cap,
           dMbr_tis = dMbr_tis, dMbr_pc = dMbr_pc,  dMut_cap = dMut_cap, dMut_tis = dMut_tis,
           dMut_pc = dMut_pc, dMskel_cap = dMskel_cap, dMskel_tis = dMskel_tis, dMskel_pc = dMskel_pc, 
           dMskin_cap = dMskin_cap, dMskin_tis = dMskin_tis, dMskin_pc = dMskin_pc, dMsoft_cap = dMsoft_cap,
           dMsoft_tis = dMsoft_tis, dMsoft_pc = dMsoft_pc, dArt_blood = dArt_blood, dVen_blood = dVen_blood,
           dMblood_pc = dMblood_pc, dMfeces = dMfeces, dMurine = dMurine), Total_lungs = Total_lungs)
  })
}

##############################################

# User must provide a string declaring the path where the vpc_data file is stored
path <- ""
input.data <- openxlsx::read.xlsx(paste(path,"biodist_data.xlsx", sep = ""), 
                                  sheet=3,colNames = TRUE, rowNames = TRUE)

# the following numbers derive from normalisation of the MPPD numbers 0.12 and 0.52
tb.depo = 0.1875 
al.depo = 0.8125
ua.depo = 0
# use average input data to represent all rats
input <-list("exposure.concentration" = rowMeans(input.data[3,]), "exposure.time" = 2,
              "weight" = 277, "dep.ua" = 0, "dep.tb" = tb.depo*rowMeans(input.data[2,]), 
              "dep.al" =  al.depo*rowMeans(input.data[2,]), 
              "Inhaled.vol.rate" = rowMeans(input.data[10,]))

# Produce one solution with mean values
params_determ <- create.params(input,stan_fit, stochastic = FALSE)
inits <- create.inits(params_determ)
events <- create.events(params_determ)

# Here we create a first solution to get the dimensions because the total instances will be 
# equal to the dimension of sample_time plus the extra events which occured at times
# not provided in the sample time vector
sample_time <- c(1e-08, 1e-04, 1e-03, 1e-02, 1e-01, 0.5, 1, 2, 6, 12, 26, 48, 72, 144, 256, 300, 
                 400, 500, 600 , 700)
solution <-  ode(times = sample_time,  func = ode.func, y = inits, parms = params_determ, 
                 custom.func = custom.func, method="lsodes",  events = events)
solution <- as.data.frame(solution[solution[,1]  %in% sample_time,1:40])
deterministic.df <- matrix(rep(NA, 17*dim(solution)[1]), ncol = 17)
deterministic.df[,1] <- solution[,1]
deterministic.df[,2] <- solution[,3] 
deterministic.df[,3] <- solution[,4] 
deterministic.df[,4] <-  solution[,5] 
deterministic.df[,5] <- (solution[,7] + solution[,8])  
deterministic.df[,6] <- (solution[,10] + solution[,11]) 
deterministic.df[,7] <- (solution[,13] + solution[,14])
deterministic.df[,8] <- (solution[,16] + solution[,17])
deterministic.df[,9] <- (solution[,19] + solution[,20])
deterministic.df[,10] <- (solution[,22] + solution[,23])
deterministic.df[,11] <- (solution[,25] + solution[,26])
deterministic.df[,12] <- (solution[,28] + solution[,29]) 
deterministic.df[,13] <- (solution[,31] + solution[,32])  
deterministic.df[,14] <- (solution[,34] + solution[,35])   
deterministic.df[,15] <- (solution[,36] + solution[,37]+ solution[,38])
deterministic.df[,16] <- solution[,39]
deterministic.df[,17] <- solution[,40]

colnames(deterministic.df) <- c( "Time", "Trachea", "BALF", "BALC", "Lavaged lungs", "Liver", "Spleen",
                         "Kidneys", "Heart", "Brain", "Uterus", "Skeleton", "Skin", "Soft tissues",
                         "Blood", "Feces", "Urine")


Nsim = 1000 # number of simulations
Nrat = 20 # number of virtual rats
ltime <- dim(solution)[1] # number of solution instances
data_time <- solution[,"time"]
Ncomp <- dim(solution)[2] # Number of compartments to plot
pred_con_tra <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_balf <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_balc <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_lav <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_li <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_spl <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_ki <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_ht <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_br <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_ut <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_skel <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_skin <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_soft <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_blood <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_feces <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))
pred_con_urine <-array(rep(NA,Nrat*ltime*Nsim),dim=c(Nrat,ltime,Nsim))

failed = list()

for (sim in 1:Nsim){
  for (rat in 1:Nrat){
    print(paste("rat   ",rat, "Nsim    ",sim))

        pred <- matrix(rep(NA, Ncomp*ltime), nrow = ltime)
        # parameter to inform about failed attempts
        failed_attempt <- 0
        # if params result in odes not solving, resample and resolve
        while( (dim(pred)[1] != ltime) | sum(is.na(pred)) ) {
         
        #params are selected stochastically because create.params samples from stan estimates
        params <- create.params(input,stan_fit)
        events <- create.events(params)
        sol  <- ode(times = sample_time,  func = ode.func, y = inits, parms = params, 
                    custom.func = custom.func, method="lsodes",  events = events, 
                    maxsteps = 50000) 
        pred <- sol[sol[,1] %in% sample_time,]
        pred
        }
        
        
        for(t in 1:ltime){
        ###Total amount of NPs in each organ
        # Amount in trachea
        pred_con_tra[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = pred[t,3] , sd = params$error1)
        # Amount in Balf
        pred_con_balf[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = pred[t,4] , sd = params$error1/2)
        
        # Amount in Balc
        pred_con_balc[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = pred[t,5] , sd = params$error1/2) 
        
        # Amount in lavaged lungs
        pred_con_lav[rat,t,sim]<-   truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,7] + pred[t,8])  , sd = params$error1)
        
        # Amount in liver
        pred_con_li[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean =  (pred[t,10] + pred[t,11]) , sd = params$error2) 
        
        # Amount in spleen
        pred_con_spl[rat,t,sim]<-  truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,13] + pred[t,14]) , sd = params$error3)  
        
        # Amount in kidneys
        pred_con_ki[rat,t,sim] <-  truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,16] + pred[t,17]) , sd = params$error2)   
        
        # Amount in heart
        pred_con_ht[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,19] + pred[t,20]) , sd = params$error3)   
        
        # Amount in brain
        pred_con_br[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,22] + pred[t,23]) , sd = params$error3)    
        
        # Amount in uterus
        pred_con_ut[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,25] + pred[t,26]) , sd = params$error3)    
        
        # Amount in skeleton
        pred_con_skel[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,28] + pred[t,29])  , sd = params$error2) 
        
        # Amount in skin
        pred_con_skin[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,31] + pred[t,32])  , sd = params$error2)  
        
        # Amount in soft tissues
        pred_con_soft[rat,t,sim] <-  truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,34] + pred[t,35])  , sd = params$error2)  
        
        # Amount in blood
        pred_con_blood[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = (pred[t,36] + pred[t,37]+ pred[t,38]), sd = params$error2)  
        
        # Amount in  feces
        pred_con_feces[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = pred[t,39], sd = params$error1)   
        
        # Amount in urine
        pred_con_urine[rat,t,sim] <- truncnorm::rtruncnorm(1, a=0, b=Inf, mean = pred[t,40], sd = params$error1)   
        }
       }
}


bag_of_data <- list( pred_con_tra, pred_con_balf, pred_con_balc, pred_con_lav, pred_con_li, 
                     pred_con_spl, pred_con_ki, pred_con_ht, pred_con_br, pred_con_ut, pred_con_skel,
                     pred_con_skin, pred_con_soft, pred_con_blood, pred_con_feces, pred_con_urine)
names(bag_of_data) <- c( "Trachea", "BALF", "BALC", "Lavaged lungs", "Liver", "Spleen",
                         "Kidneys", "Heart", "Brain", "Uterus", "Skeleton", "Skin", "Soft tissues",
                         "Blood", "Feces", "Urine")
comp_names <- names(bag_of_data) 

# File where data are stored
path <- ""
### load data
biodist_data <- openxlsx::read.xlsx(paste(path,"biodist_data.xlsx", sep = ""),
                                    sheet=1,colNames = TRUE,rowNames = TRUE)
sd_data <- openxlsx::read.xlsx(paste(path,"biodist_data.xlsx", sep = ""),
                               sheet=2,colNames = TRUE,rowNames = TRUE)

feces <- openxlsx::read.xlsx(paste(path,"feces.xlsx", sep = ""),
                             sheet=2,colNames = TRUE)[,2]*input.data[1,5]
urine<- openxlsx::read.xlsx(paste(path,"urine.xlsx", sep = "")
                            , sheet=2,colNames = TRUE)[,2]*input.data[7,5]

excreta_time <- c(3.5, 7, 10.5, 14, 17.5, 21, 24.5, 27)*24
biodist_time <- c(2, 6, 26, (7*24+2), (28*24+2))

excreta.df <- as.data.frame(cbind(excreta_time, feces, urine))
colnames(excreta.df) <- c("Time", "Feces", "Urine")

data.df <- data.frame(cbind(biodist_time, biodist_data))
colnames(data.df) <- c("Time", colnames(biodist_data))

sd.data.df <- data.frame(cbind(biodist_time, sd_data))
colnames(data.df) <- c("Time", colnames(sd_data))

# Set the path where the plots will be stored
setwd(path)

counter <-1
for (dat in bag_of_data) {
    # Get the compartment name to be plotted
     comp_name <- comp_names[counter]
     # Define the save name
     save_name <- paste0(comp_name, "_vpc.png", sep="")
     pred_con <- dat
     
     
     
     
     ##########################
     # Calculation of 95 % CI of the 50th quantile
     con<-matrix(rep(NA,ltime*Nsim), nrow = ltime)
     ymin<- rep(NA,ltime)
     ymax<- rep(NA,ltime)
  
     for (i in 1:ltime){
       for (j in 1:Nsim){
         con[i,j]<-quantile(pred_con[,i,j],probs=0.5)
       }
     }
  
     for (i in 1:ltime){
        con[i,]<-sort(con[i,])
        ymin[i]<-quantile(con[i,],probs=0.025)
        ymax[i]<-quantile(con[i,],probs=0.975)
     }
    
    q50<-data.frame(time=data_time,lo=ymin,hi=ymax)
    ############################  
    # Calculation of 95 % CI of the 5th quantile
    
    con<-matrix(rep(NA,ltime*Nsim), nrow = ltime)
    ymin<- rep(NA,ltime)
    ymax<- rep(NA,ltime)
    
    for (i in 1:ltime){
      for (j in 1:Nsim){
        con[i,j]<-quantile(pred_con[,i,j],probs=0.05)
      }
    }
    
    for (i in 1:ltime){
      con[i,]<-sort(con[i,])
      ymin[i]<-quantile(con[i,],probs=0.025)
      ymax[i]<-quantile(con[i,],probs=0.975)
    }
    
    q05<-data.frame(time=data_time,lo=ymin,hi=ymax)
    #################################  
    # Calculation of 95 % CI of the 95th quantile
    con<-matrix(rep(NA,ltime*Nsim), nrow = ltime)
    ymin<- rep(NA,ltime)
    ymax<- rep(NA,ltime)
    
    for (i in 1:ltime){
      for (j in 1:Nsim){
        con[i,j]<-quantile(pred_con[,i,j],probs=0.95)
      }
    }
    
    for (i in 1:ltime){
      con[i,]<-sort(con[i,])
      ymin[i]<-quantile(con[i,],probs=0.025)
      ymax[i]<-quantile(con[i,],probs=0.975)
    }
    
    q95<-data.frame(time=data_time,lo=ymin,hi=ymax)
  ############################
    # Mean values of predictions from deterministic.df model
    use_comp <- colnames(deterministic.df)[counter+1]
    mean_pred = data.frame(deterministic.df[,c("Time", use_comp)])
    colnames(mean_pred) = c("time", "value")
    
  if(!(comp_name %in% c("Feces", "Urine"))){
    use_comp <- colnames(data.df)[counter+1]
    df1 <- as.data.frame(cbind(data.df[,c("Time",use_comp)], sd.data.df[,use_comp]))
    colnames(df1) <- c("Time", "Mean", "Sd")
    my_plot <- ggplot() +   
          geom_line(data=mean_pred, aes(x=time, y=value, linetype = " Prediction mean"),
                    size=1.2)+
          geom_ribbon(data=q50,aes(x=time, ymin = lo, ymax = hi, fill = "50th percentile"),
                      inherit.aes=FALSE, alpha = 0.2) + 
          geom_ribbon(data=q05,aes(x=time, ymin = lo, ymax = hi, fill = "5th percentile"),
                      inherit.aes=FALSE, alpha = 0.2) + 
          geom_ribbon(data=q95,aes(x=time, ymin = lo, ymax = hi, fill="95th percentile"),
                      inherit.aes=FALSE,alpha = 0.2) + 
         geom_point(data = df1, aes(x = Time, y=Mean),size=5)+
         geom_errorbar(data = df1, aes(x = Time, ymin=ifelse((Mean-Sd)>0,Mean-Sd,0), ymax=Mean+Sd),size=1)+
         labs(title = rlang::expr(!!comp_name), y = "TiO2 (ug)", x = "Time (in hours)") +
         scale_fill_manual("Prediction Ribbons", values = c( "50th percentile" = 1, 
                                                  "5th percentile" = 2,"95th percentile" = 3)) + 
        scale_linetype_manual("Line", values = c(" Prediction mean" = 1))+
        scale_colour_manual("Point", values = c("Biodistribtion data" = 1))+
        theme(plot.title =element_text(hjust = 0.5, size=30, face="bold"),
              axis.title.y =element_text(hjust = 0.5, size=20, face="bold"),
              axis.text.y=element_text(size=18),
              axis.title.x =element_text(hjust = 0.5, size=20, face="bold"),
              axis.text.x=element_text(size=18),
              legend.title=element_text(hjust = 0.01, size=20), 
              legend.text=element_text(size=18))
        png(rlang::expr(!!save_name), width = 15, height = 10, units = 'in', res = 500)
        print(my_plot)
  } else{
      observed <- excreta.df[,c("Time",colnames(excreta.df)[counter-13])]
      colnames(observed) <- c("Time", "mean")
      my_plot <- ggplot(observed, aes(x=Time, y=mean, colour="Biodistribtion data"))+
        geom_point(shape=19, size=4) +   
        #geom_bar(aes(ymin=ifelse((mean-sd)>0,mean-sd,0), ymax=mean+sd), width=.1) +
        geom_line(data=mean_pred, aes(x=time, y=value, linetype = " Prediction mean"), 
                  size=1.2)+
        geom_ribbon(data=q50,aes(x=time, ymin = lo, ymax = hi, fill = "50th percentile"),
                    inherit.aes=FALSE, alpha = 0.2) + 
        geom_ribbon(data=q05,aes(x=time, ymin = lo, ymax = hi, fill = "5th percentile"),
                    inherit.aes=FALSE, alpha = 0.2) + 
        geom_ribbon(data=q95,aes(x=time, ymin = lo, ymax = hi, fill="95th percentile"),
                    inherit.aes=FALSE,alpha = 0.2) + 
        labs(title = rlang::expr(!!comp_name), y = "TiO2 (ug)", x = "Time (in hours)") +
        scale_fill_manual("Prediction Ribbons", values = c( "50th percentile" = 1, 
                                                "5th percentile" = 2,"95th percentile" = 3)) +
        scale_linetype_manual("Line", values = c(" Prediction mean" = 1))+
        scale_colour_manual("Point", values = c("Biodistribtion data" = 1))+
        theme(plot.title =element_text(hjust = 0.5, size=30, face="bold"),
              axis.title.y =element_text(hjust = 0.5, size=20, face="bold"),
              axis.text.y=element_text(size=18),
              axis.title.x =element_text(hjust = 0.5, size=20, face="bold"),
              axis.text.x=element_text(size=18),
              legend.title=element_text(hjust = 0.01, size=20), 
              legend.text=element_text(size=18))
      png(rlang::expr(!!save_name), width = 15, height = 10, units = 'in', res = 500)
      print(my_plot)
    
  }
  dev.off()
  counter <- counter +1
}
      
