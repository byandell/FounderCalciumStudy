ui <- function() {
  fluidPage(
    
    titlePanel("Founder Calcium / Protein Study"),
    sidebarLayout(
      sidebarPanel(
        tagList(
          uiOutput("intro"),
          selectInput("order", "Order traits by",
                          c("p_overall", "p_sex_diet", "p_diet", "p_sex", "variability", "alphabetical", "original"),
                          "p_overall")),
          uiOutput("strains"),
          sliderInput("height", "Plot height (in):", 3, 10, 6, step = 1),
          uiOutput("downloadPlotUI"),
          fluidRow(
            shiny::column(
              6,
              uiOutput("tablename")),
            shiny::column(
              3,
              shiny::downloadButton("downloadTable", "Summary")))),
        uiOutput("trait")),
      
      # Main panel for displaying outputs ----
      mainPanel(
        uiOutput("outs")
      )
    )
  )
}

server <- function(session, input, output) {
  
  output$intro <- renderUI({
    tagList("This founder dataset consists of ",
            shiny::a("8 CC mice strains", href = "https://www.jax.org/news-and-insights/2009/april/the-collaborative-cross-a-powerful-systems-genetics-tool"),
            "and both sexes with measurement of calcium and protein expression.",
            "The calcium and protein measurements are on different sets of mice, with the focus on correlation fo their signal across strain and sex."
            "Select a protein and a calcium trait after deciding on trait order.",
            "Traits window supports partial matching to find desired traits.",
            "Facet plots by sex and subset strains if desired.",
            "Plots and data means (for selected traits) and data summaries (for whole measurement set) can be downloaded.",
            "See",
            shiny::a("Attie Lab Diabetes Database", href = "http://diabetes.wisc.edu/"),
            "for earlier study.",
            "GigHub:", shiny::a("byandell/FounderDietStudy",
                                        href = "https://github.com/byandell/FounderDietStudy"))
  })
  
  output$strains <- renderUI({
    choices <- names(CCcolors)
    checkboxGroupInput("strains", "Strains",
                       choices = choices, selected = choices, inline = TRUE)
  })
  
  # Trait summaries (for ordering traits, and summary table)
  dataset <- reactive({
    req(input$datatype)
    traitdata %>%
      filter(datatype %in% input$datatype)
  })
  traitarrange <- reactive({
    req(input$order, input$datatype)
    out <- traitsumdata %>%
      filter(datatype %in% input$datatype)
    switch(input$order,
           variability = 
             out %>%
             arrange(desc(rawSD)),
           alphabetical = 
             out %>%
             arrange(trait),
           original = 
             out,
           p_overall = 
             out %>% 
             arrange(overall),
           p_sex = 
             out %>% 
             arrange(strain.sex),
           p_diet = 
             out %>% 
             arrange(strain.diet),
           p_sex_diet =
             out %>% 
             arrange(strain.sex.diet))
  })
  traitorder <- reactive({
    traitarrange()$trait
  })
  
  # Select traits
  output$trait <- renderUI({
    req(traitorder(), input$order, dataset())
    selectizeInput("trait", "Traits:", choices = NULL, multiple = TRUE)
  })
  observeEvent({
    req(dataset(), input$order)
    },
    {
    updateSelectizeInput(session, "trait", choices = traitorder(),
                         server = TRUE)
  })
  
  # Data for selected traits
  datatraitslong <- reactive({
    req(dataset(), input$trait, input$strains)
    dataset() %>%
      filter(trait %in% input$trait,
             strain %in% input$strains)
  })
  datatraits <- reactive({
    req(datatraitslong(), input$trait)
    ltrait <- length(input$trait)
    datatraitslong() %>%
      mutate(trait = abbreviate(trait, ceiling(60 / ltrait))) %>%
      unite(sex_diet, sex, diet)
  })
  
  # Output: Plots or Data
  output$outs <- shiny::renderUI({
    shiny::tagList(
      shiny::radioButtons("button", "", c("Plots", "Pair Plots", "Data Means", "Data Summary"), "Plots", inline = TRUE),
      shiny::conditionalPanel(
        condition = "input.button == 'Plots'",
        shiny::uiOutput("plots")),
      shiny::conditionalPanel(
        condition = "input.button == 'Pair Plots'",
        shiny::uiOutput("scatPlot")),
      shiny::conditionalPanel(
        condition = "input.button == 'Data Means'",
        DT::dataTableOutput("datatable")),
      shiny::conditionalPanel(
        condition = "input.button == 'Data Summary'",
        DT::dataTableOutput("tablesum")))
  })
  
  # Plots
  distplot <- reactive({
    if(!isTruthy(dataset()) | !isTruthy(input$trait)) {
      return(ggplot())
    }
    if(!all(input$trait %in% dataset()$trait)) {
      return(ggplot())
    }
    ltrait <- length(input$trait)
    
    req(input$facet)
    p <- ggplot(datatraits())
    switch(input$facet,
           strain = {
             p <- p +
               aes(sex_diet, value, fill = sex_diet) +
               geom_jitter(size = 3, shape = 21, color = "black", alpha = 0.65) +
               facet_grid(datatype + trait ~ strain, scales = "free_y") +
               scale_fill_manual(values = sex_diet_colors)
           },
           sex_diet = {
             p <- p +
               aes(strain, value, fill = strain) +
               geom_jitter(size = 3, shape = 21, color = "black", alpha = 0.65) +
               facet_grid(datatype + trait ~ sex_diet, scales = "free_y") +
               scale_fill_manual(values = CCcolors)
           })
    p +
      theme(legend.position = "none",
            axis.text.x = element_text(angle = 45, vjust = 1, hjust=1)) +
      ylab(ifelse(ltrait == 1, input$trait, "Trait Value")) +
      ggtitle(paste0(paste(input$datatype, collapse = ","),
                     " data for trait",
                     ifelse(ltrait > 1, "s ", " "),
                     paste(abbreviate(input$trait, ceiling(60 / ltrait)),
                           collapse = ", ")))
  })
  output$distPlot <- renderPlot({
    distplot()
  })
  output$plots <- renderUI({
    req(input$height)
    plotOutput("distPlot", height = paste0(input$height, "in"))
  })
  output$downloadPlotUI <- renderUI({
    ltrait <- length(req(input$trait))
    filename <- paste0(paste(req(input$datatype), collapse = "."),
                       "_",
                       paste(abbreviate(input$trait, ceiling(60 / ltrait)),
                             collapse = "."))
    fluidRow(
      shiny::column(
        6,
        shiny::textAreaInput("plotname", "File Prefix", filename)),
      shiny::column(
        3,
        downloadButton("downloadPlot", "Plots")),
      shiny::column(
        3,
        downloadButton("downloadMean", "Means")))
  })
  output$downloadPlot <- shiny::downloadHandler(
    filename = function() {
      paste0(shiny::req(input$plotname), ".pdf") },
    content = function(file) {
      req(input$height)
      grDevices::pdf(file, width = 9, height = input$height)
      print(distplot())
      grDevices::dev.off()
    })
  
  # Data Table
  datameans <- reactive({
    datatraits() %>%
      group_by(strain, sex_diet, trait) %>%
      summarize(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
      ungroup() %>%
      mutate(value = signif(value, 4)) %>%
      pivot_wider(names_from = "strain", values_from = "value") %>%
      arrange(trait, sex_diet)
  })
  output$datatable <- DT::renderDataTable(
    datameans(),
    escape = FALSE,
    options = list(scrollX = TRUE, pageLength = 10))
  output$tablesum <- DT::renderDataTable(
    traitarrange() %>%
      mutate(across(where(is.numeric), function(x) signif(x, 4))),
    escape = FALSE,
    options = list(scrollX = TRUE, pageLength = 10))
  output$tablename <- renderUI({
    filename <- req(input$datatype)
    shiny::textInput("tablename", "Summary File Prefix", filename)
  })
  output$downloadMean <- shiny::downloadHandler(
    filename = function() {
      paste0(shiny::req(input$plotname), ".csv") },
    content = function(file) {
      utils::write.csv(datameans(), file, row.names = FALSE)
    }
  )
  output$downloadTable <- shiny::downloadHandler(
    filename = function() {
      req(input$datatype)
      paste0(shiny::req(input$tablename), ".csv") },
    content = function(file) {
      utils::write.csv(traitarrange(), file, row.names = FALSE)
    }
  )
  
  output$pair <- renderUI({
    # Somehow when input$height is changed this is reset.
    req(input$trait)
    if(length(input$trait) < 2)
      return(NULL)
    choices <- as.data.frame(combn(input$trait, 2)) %>%
      mutate(across(
        everything(), 
        function(x) {
          c(paste(x, collapse = " ON "),
            paste(rev(x), collapse = " ON "))
        })) %>%
      unlist() %>%
      as.vector()
    
    selectInput("pair", "Select pairs for scatterplots",
                choices = choices, selected = choices[1],
                multiple = TRUE, width = '100%')
  })
  output$scatPlot <- renderUI({
    req(input$trait, input$datatype, input$order)
    tagList(
      uiOutput("pair"),
      plotOutput("scatplot", height = paste0(input$height, "in"))
    )
  })
  output$scatplot <- renderPlot({
    req(input$trait, datatraitslong(), input$pair)
    if(!isTruthy(input$pair)) {
      return(ggplot())
    }
    
    dat <- 
      map(
        input$pair,
        function(x) {
          # Split trait pair by colon
          x <- str_split(x, " ON ")[[1]][2:1]
          # create out with columns for each trait pair
          out <- datatraitslong() %>%
            filter(trait %in% x) %>%
            mutate(trait = c(x[1],x[2])[match(trait, x)]) %>%
            select(strain, number, sex, diet, trait, value) %>%
            pivot_wider(names_from = "trait", values_from = "value") %>%
            unite(sex_diet, sex, diet)
          # create plot
          ggplot(out) +
            aes(.data[[x[1]]], .data[[x[2]]], fill = strain, col = strain) +
            geom_smooth(method = "lm", se = FALSE, formula = "y ~ x") +
            geom_point(size = 3, shape = 21, color = "black", alpha = 0.65) +
            scale_color_manual(values = CCcolors) +
            facet_grid(. ~ sex_diet) +
            theme(legend.position = "none")
        })
    # Patch plots together by rows
    patchwork::wrap_plots(dat, nrow = length(dat))
  })
}

shiny::shinyApp(ui = ui, server = server)
